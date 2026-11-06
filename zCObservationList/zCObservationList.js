import { api, track, wire, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import { formatObservationData, buildGroup, decorateRow, toOptions, withDisplayHints, snapshotAll, hasDirtyRows, buildSavePayload, buildImagePayload, buildRemarks, assignDisplayOrder, isRecordId, newRow, newTempId, reduceError, compressImage, createPreview, blobToBase64, fireInParallel } from './helper.js';

import getObservations from '@salesforce/apex/ZC_Helper.getObservations';
import saveObservations from '@salesforce/apex/ZC_Helper.saveObservations';
import saveImageObservations from '@salesforce/apex/ZC_Helper.saveImageObservations';
import removeObservations from '@salesforce/apex/ZC_Helper.removeObservations';

const ACCEPTED_IMAGE_TYPES = '.jpg,.jpeg,.png';
const MAX_FILES_PER_UPLOAD = 5;

const IMAGE_STATUS = {
    pending: { label: 'Not saved yet', className: 'upload-status upload-status_pending' },
    saving: { label: 'Saving...', className: 'upload-status upload-status_saving' },
    failed: { label: 'Not saved - click Save Observations to retry', className: 'upload-status upload-status_failed' }
};

export default class ZC_ObservationList extends LightningElement {

    @api selectedVisitId;
    @api observationMaster;
    @api previousObservations;

    @track observationData = [];
    @track savedSnapshots = {}; // row key -> last saved field values
    @track pendingImages = new Map(); // image key -> compressed image of a new image, kept until it is saved
    @track inFlightKeys = new Set(); // keys of rows a running save is inserting
    @track deletedTempKeys = new Set(); // keys of unsaved rows removed while a save may still be inserting them
    @track removalQueue = Promise.resolve(); // removals run one after another, in the background

    @track acceptedImageTypes = ACCEPTED_IMAGE_TYPES;
    @track observationRefresh;
    @track loadedVisitId;
    @track isSaving = false;
    @track isPreparingImages = false;
    @track removalsInProgress = 0;
    @track lastUnsavedState;

    get mainCategoryOptions() {
        return toOptions(this.observationMaster);
    }

    get showNoObsButton() {
        return this.observationData.length <= 0;
    }

    get hasUnsavedChanges() {
        return hasDirtyRows(this.observationData, this.savedSnapshots);
    }

    get isBusy() {
        return this.isSaving || this.isPreparingImages;
    }

    get disableUpload() {
        return this.isPreparingImages;
    }

    get disableSave() {
        return this.isBusy || !this.hasUnsavedChanges;
    }

    get disableSubmit() {
        return this.isBusy || this.hasUnsavedChanges;
    }

    get saveLabel() {
        return this.isSaving ? 'Saving...' : 'Save Observations';
    }


    @wire(getObservations, { visitId: '$selectedVisitId' })
    wiredObservationData(result) {
        this.observationRefresh = result;
        const { data, error } = result;

        if (data) {
            // Server data never overwrites unsaved edits, new images or running work of the visit that is loaded
            if (this.loadedVisitId !== this.selectedVisitId || (!this.isSaving && !this.removalsInProgress && !this.hasUnsavedChanges)) {
                this.applyServerData(data);
            }
        }
        else if (error) {
            console.error('Error loading observations:', error);
            this.showToast('Unable to load observations. ' + reduceError(error), 'error');
        }
    }


    renderedCallback() {
        const hasUnsavedChanges = this.hasUnsavedChanges;
        if (hasUnsavedChanges !== this.lastUnsavedState) {
            this.lastUnsavedState = hasUnsavedChanges;
            this.notifyParent({ hasUnsavedChanges });
        }
    }


    applyServerData(data) {
        const formatted = formatObservationData(data, this.observationMaster);

        // A background refresh of the same visit keeps the keys and previews already on screen, so nothing re-renders
        if (this.loadedVisitId === this.selectedVisitId) {
            const groupByDocument = new Map();
            const keyById = new Map();
            this.observationData.forEach(group => {
                groupByDocument.set(group.ContentDocumentId, group);
                group.Observations.forEach(row => keyById.set(row.Id, row.key));
            });
            formatted.forEach(group => {
                const current = groupByDocument.get(group.ContentDocumentId);
                if (current) {
                    group.key = current.key;
                    group.VersionDataUrl = current.VersionDataUrl || group.VersionDataUrl;
                }
                group.Observations.forEach(row => {
                    row.key = keyById.get(row.Id) ?? row.key;
                });
            });
        }

        this.loadedVisitId = this.selectedVisitId;
        this.observationData = formatted;
        this.savedSnapshots = snapshotAll(this.observationData);
        this.pendingImages.clear();
        this.deletedTempKeys.clear();
    }


    findGroup(groupKey) {
        return this.observationData.find(group => group.key === groupKey) || null;
    }

    findRow(rowKey) {
        for (const group of this.observationData) {
            const row = group.Observations.find(obs => obs.key === rowKey);
            if (row) return row;
        }
        return null;
    }


    clearFieldError(field) {
        field.setCustomValidity('');
        field.reportValidity();
    }


    handleCategoryChange(event) {
        const cdRow = this.findRow(event.target.dataset.rowId);
        if (!cdRow) return;

        this.clearFieldError(event.target);
        cdRow.Category__c = event.detail.value;
        cdRow.Sub_Category__c = null;
        cdRow.Observation_Non_Compliance__c = null;
        decorateRow(cdRow, this.observationMaster);
    }


    handleSubCategoryChange(event) {
        const cdRow = this.findRow(event.target.dataset.rowId);
        if (!cdRow) return;

        this.clearFieldError(event.target);
        cdRow.Sub_Category__c = event.detail.value;
        cdRow.Observation_Non_Compliance__c = null;
        decorateRow(cdRow, this.observationMaster);
    }


    handleObservationAndCommentsChange(event) {
        const cdRow = this.findRow(event.target.dataset.rowId);
        if (!cdRow) return;

        if (event.target.dataset.fieldName === 'Comments') {
            cdRow.Agent_Comments__c = event.detail.value;
            return;
        }

        this.clearFieldError(event.target);
        cdRow.Observation_Non_Compliance__c = event.detail.value;
        cdRow.Observations_from_Previous_Visit__c = Array.isArray(this.previousObservations) && this.previousObservations.some(prev =>
            (prev?.Category__c ?? '') === (cdRow.Category__c ?? '') &&
            (prev?.Sub_Category__c ?? '') === (cdRow.Sub_Category__c ?? '') &&
            (prev?.Observation_Non_Compliance__c ?? '') === (cdRow.Observation_Non_Compliance__c ?? '')
        );

        if (cdRow.Observations_from_Previous_Visit__c) {
            this.showToast('Selected observation is found in previous visit. Please confirm if you want to mark it as repeated!', 'warning');
        }
        else {
            cdRow.X2x_Penalty_Applicable__c = false;
        }
        decorateRow(cdRow, this.observationMaster);
    }


    handleCornerClick(event) {
        const cdRow = this.findRow(event.currentTarget.dataset.rowId);
        if (!cdRow) return;

        cdRow.X2x_Penalty_Applicable__c = !cdRow.X2x_Penalty_Applicable__c;
        cdRow.RepeatedLabel = cdRow.X2x_Penalty_Applicable__c ? 'Repeated' : 'Repeated?';
    }


    handleAddObservationRow(event) {
        const group = this.findGroup(event.currentTarget.dataset.rowId);
        if (!group) return;

        group.Observations.push(decorateRow(newRow(), this.observationMaster));
        this.observationData = withDisplayHints([...this.observationData]);
    }


    /**
     * Compresses the picked images one at a time (keeps memory low on iPad) and shows each one with an empty row
     * straight away. Nothing is sent to the server until Save Observations.
     */
    async handleFilesChange(event) {
        const files = Array.from(event.detail?.files || event.target.files || []);
        if (!files.length) return;

        if (files.length > MAX_FILES_PER_UPLOAD) {
            this.showToast(`Maximum ${MAX_FILES_PER_UPLOAD} files can be uploaded at a time`, 'error');
            return;
        }

        this.isPreparingImages = true;
        this.notifyParent({ showSpinner: true });
        const failedFiles = [];

        try {
            for (const file of files) {
                try {
                    // eslint-disable-next-line no-await-in-loop
                    const blob = await compressImage(file);
                    // eslint-disable-next-line no-await-in-loop
                    const preview = await createPreview(blob);

                    const key = newTempId('NewImg');
                    const group = buildGroup(key, key, file.name, preview);
                    group.isNew = true;
                    group.uploadStatus = IMAGE_STATUS.pending;
                    group.Observations.push(decorateRow(newRow(), this.observationMaster));

                    this.pendingImages.set(key, { blob, name: file.name });
                    this.observationData = withDisplayHints([...this.observationData, group]);
                }
                catch (error) {
                    console.error('Unable to prepare image ' + file.name + ':', error);
                    failedFiles.push(file.name);
                }
            }
        }
        finally {
            this.isPreparingImages = false;
            this.notifyParent({ showSpinner: false });
        }

        if (failedFiles.length) {
            this.showToast('These images could not be processed, please try again: ' + failedFiles.join(', '), 'error');
        }
    }


    /**
     * New images are saved with one Apex call per image (each call saves the image with its rows). All image calls
     * are started at once without waiting for each other, so they run in parallel. Then one call saves the edited
     * rows and refreshes the Visit remarks. An image that fails stays on screen marked as not saved and is retried
     * by the next save; the others are kept.
     */
    async handleSaveAll() {
        if (this.isBusy) return;

        this.isSaving = true;
        const visitId = this.selectedVisitId;
        const errors = [];

        try {
            assignDisplayOrder(this.observationData);
            const newGroups = this.observationData.filter(group => group.isNew && group.Observations.length && this.pendingImages.has(group.key));
            if (newGroups.length) {
                // Base64 is prepared for every image first, so nothing delays the calls once they start
                const prepared = await Promise.all(newGroups.map(group => this.prepareImageSave(group.key).catch(error => {
                    errors.push(error);
                    return null;
                })));
                const results = await fireInParallel(prepared.filter(Boolean).map(save => () => this.sendImageSave(visitId, save)));
                results.forEach(result => {
                    if (!result.ok) errors.push(result.error);
                });
            }

            if (visitId === this.loadedVisitId) {
                await this.saveRows(visitId).catch(error => errors.push(error));
            }
        }
        finally {
            this.isSaving = false;
        }

        if (visitId !== this.loadedVisitId) return;

        if (errors.length) {
            errors.forEach(error => console.error('Save error:', error));
            this.showToast('Some observations could not be saved. Click Save Observations to retry. ' + reduceError(errors[0]), 'error');
        }
        else {
            this.showToast('Recorded Observations are saved.', 'success');
        }

        if (this.observationRefresh) {
            refreshApex(this.observationRefresh).catch(error => console.error('Background refresh failed:', error));
        }
    }


    // Builds everything one image call needs; the rows are marked as being inserted from here on
    async prepareImageSave(groupKey) {
        const group = this.findGroup(groupKey);
        const image = this.pendingImages.get(groupKey);
        if (!group || !image) return null;

        const { payload, sent } = buildImagePayload(group);
        sent.forEach(({ key }) => this.inFlightKeys.add(key));
        group.uploadStatus = IMAGE_STATUS.saving;

        try {
            const fileContent = await blobToBase64(image.blob);
            return { groupKey, sent, fileName: image.name, jsonData: JSON.stringify(payload), fileContent };
        }
        catch (error) {
            sent.forEach(({ key }) => this.inFlightKeys.delete(key));
            group.uploadStatus = IMAGE_STATUS.failed;
            throw error;
        }
    }


    async sendImageSave(visitId, { groupKey, sent, fileName, jsonData, fileContent }) {
        try {
            const result = await saveImageObservations({ visitId, jsonData, fileName, fileContent });
            if (visitId === this.loadedVisitId) this.applyImageResult(groupKey, sent, result);
        }
        catch (error) {
            const current = this.findGroup(groupKey);
            if (current) current.uploadStatus = IMAGE_STATUS.failed;
            throw error;
        }
        finally {
            sent.forEach(({ key }) => this.inFlightKeys.delete(key));
        }
    }


    applyImageResult(groupKey, sent, result) {
        const upload = result?.uploads?.[0];
        const idMap = result?.idMap || {};
        if (!upload) throw new Error('The image was not saved.');

        this.pendingImages.delete(groupKey);
        const group = this.findGroup(groupKey);

        // The whole image was removed while it was being saved: remove what was just created
        if (!group) {
            sent.forEach(({ key }) => this.deletedTempKeys.delete(key));
            this.queueRemoval(this.loadedVisitId, Object.values(idMap), upload.contentDocumentId);
            return;
        }

        group.ContentDocumentId = upload.contentDocumentId;
        group.isNew = false;
        group.uploadStatus = null;
        this.applySaveResult(sent, idMap, result?.observationsDisplayOrderMap || {});
    }


    // Sends only the new or changed rows of images that are already saved; this call also refreshes the remarks
    async saveRows(visitId) {
        const { groups, sent } = buildSavePayload(this.observationData, this.savedSnapshots);
        sent.forEach(({ key }) => this.inFlightKeys.add(key));

        try {
            const result = await saveObservations({ visitId, jsonData: JSON.stringify(groups) });
            if (visitId === this.loadedVisitId) this.applySaveResult(sent, result?.idMap || {}, result?.observationsDisplayOrderMap || {});
        }
        finally {
            sent.forEach(({ key }) => this.inFlightKeys.delete(key));
        }
    }


    /**
     * Records what was saved. Rows keep their key, only the temporary Id is replaced by the record Id.
     * The snapshot is the one taken when the save started, so edits made while it ran stay unsaved
     * and the next save updates the record instead of inserting it again.
     */
    applySaveResult(sent, idMap, observationsDisplayOrderMap) {
        const snapshots = { ...this.savedSnapshots };
        const orphanIds = [];

        sent.forEach(({ key, id, snapshot }) => {
            const savedId = idMap[id] || id;

            // Row was removed from the screen while it was being inserted: remove the new record too
            if (this.deletedTempKeys.delete(key)) {
                if (savedId !== id) orphanIds.push(savedId);
                return;
            }

            const row = this.findRow(key);
            if (row) {
                row.Id = savedId;
                if (observationsDisplayOrderMap[id] !== undefined) {
                    row.Observations_Display_Order__c = observationsDisplayOrderMap[id];
                }
            }
            snapshots[key] = snapshot;
        });

        this.savedSnapshots = snapshots;
        this.observationData = withDisplayHints([...this.observationData]);
        if (orphanIds.length) this.queueRemoval(this.loadedVisitId, orphanIds, null);
        this.notifyParent({ remarks: buildRemarks(this.observationData) });
    }


    // Removes the row from the screen immediately and deletes it in the background; restores it if that fails
    handleRemoveRow(event) {
        const rowKey = event.currentTarget.dataset.rowId;
        const groupIndex = this.observationData.findIndex(item => item.Observations.some(obs => obs.key === rowKey));
        if (groupIndex === -1) return;

        const group = this.observationData[groupIndex];
        const rowIndex = group.Observations.findIndex(obs => obs.key === rowKey);
        const [row] = group.Observations.splice(rowIndex, 1);
        const groupEmptied = group.Observations.length === 0;

        if (groupEmptied) this.observationData.splice(groupIndex, 1);
        this.observationData = withDisplayHints([...this.observationData]);
        this.notifyParent({ remarks: buildRemarks(this.observationData) });

        const isSavedRow = isRecordId(row.Id);
        if (!isSavedRow && this.inFlightKeys.has(rowKey)) this.deletedTempKeys.add(rowKey);

        // A new image is not on the server yet (if its save is running, the result removes what it created)
        if (group.isNew) {
            if (groupEmptied && !this.inFlightKeys.has(rowKey)) this.pendingImages.delete(group.key);
            return;
        }

        const contentDocumentId = groupEmptied ? group.ContentDocumentId : null;
        if (!isSavedRow && !contentDocumentId) return;

        this.queueRemoval(this.loadedVisitId, isSavedRow ? [row.Id] : [], contentDocumentId, { visitId: this.loadedVisitId, rowKey, row, rowIndex, group, groupIndex });
    }


    /**
     * Removals run one after another in the background, separately from saves, so they never hold up Save.
     * Running them in order lets the server see that an image is no longer used once its last row is gone.
     */
    queueRemoval(visitId, observationIds, contentDocumentId, restoreEntry) {
        this.removalsInProgress++;

        this.removalQueue = this.removalQueue
            .then(() => removeObservations({ visitId, observationIds, contentDocumentId }))
            .then(() => {
                if (!restoreEntry) return;
                const snapshots = { ...this.savedSnapshots };
                delete snapshots[restoreEntry.rowKey];
                this.savedSnapshots = snapshots;
            })
            .catch(error => {
                console.error('Remove error:', error);
                if (restoreEntry) {
                    this.restoreRow(restoreEntry);
                    this.showToast('Unable to remove the observation, it has been restored. ' + reduceError(error), 'error');
                }
            })
            .finally(() => {
                this.removalsInProgress--;
            });
    }


    restoreRow(entry) {
        if (entry.visitId !== this.loadedVisitId) return;

        const data = [...this.observationData];
        let group = data.find(item => item.key === entry.group.key);

        if (!group) {
            group = { ...entry.group, Observations: [] };
            data.splice(Math.min(entry.groupIndex, data.length), 0, group);
        }
        group.Observations.splice(Math.min(entry.rowIndex, group.Observations.length), 0, entry.row);

        this.observationData = withDisplayHints(data);
        this.notifyParent({ remarks: buildRemarks(this.observationData) });
    }


    async handleNoObservation(event) {
        const status = event.currentTarget.dataset.status;
        this.notifyParent({ showSpinner: true });
        await this.removalQueue;
        this.notifyParent({ showSpinner: true, status });
    }


    // Waits only for removals still running in the background, then hands over to the parent
    async handleSubmitVisit(event) {
        const status = event.currentTarget.dataset.status;

        if (this.reportMissingFields()) {
            this.showToast('Kindly ensure all fields in recorded observations are filled', 'error');
            return;
        }

        this.notifyParent({ showSpinner: true });
        await this.removalQueue;
        this.notifyParent({ showSpinner: true, status: status, remarks: buildRemarks(this.observationData) });
    }


    // Highlights every empty required field and brings the first one into view; returns true if any is missing
    reportMissingFields() {
        let firstMissing = null;

        this.template.querySelectorAll('lightning-combobox[data-required]').forEach(field => {
            const missing = !field.value;
            field.setCustomValidity(missing ? 'Complete this field.' : '');
            field.reportValidity();
            if (missing && !firstMissing) firstMissing = field;
        });

        if (firstMissing) {
            firstMissing.scrollIntoView({ behavior: 'smooth', block: 'center' });
            firstMissing.focus();
        }
        return firstMissing !== null;
    }


    handleCreateModifyCVR() {
        this.notifyParent({ displayCVRModal: true, remarks: buildRemarks(this.observationData) });
    }


    notifyParent(detail) {
        this.dispatchEvent(new CustomEvent('zcobservationlistevent', { detail }));
    }


    showToast(message, variant) {
        const title = variant === 'success' ? 'Success!' : variant === 'error' ? 'Error!' : 'Warning!';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}