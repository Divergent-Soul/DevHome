import { processImage } from 'lightning/mediaUtils';

const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

// Fields that make a row "changed"; also what a saved snapshot holds
const ROW_FIELDS = ['Category__c', 'Sub_Category__c', 'Observation_Non_Compliance__c', 'Agent_Comments__c', 'Observations_from_Previous_Visit__c', 'X2x_Penalty_Applicable__c', 'Observations_Display_Order__c'];

// Compressed images stay under this size, so one image per request is far below the request limit
const TARGET_IMAGE_BYTES = 1024 * 1024;
const COMPRESS_OPTIONS = {
    resizeMode: 'contain',
    resizeStrategy: 'reduce',
    targetWidth: 1500,
    targetHeight: 1500,
    imageSmoothingEnabled: true,
    preserveTransparency: false,
    backgroundColor: 'white'
};
const QUALITY_SEARCH_STEPS = 6;

// Small preview shown on screen; never sent to the server
const PREVIEW_OPTIONS = { ...COMPRESS_OPTIONS, targetWidth: 500, targetHeight: 500, compressionQuality: 0.7 };


export function isRecordId(value) {
    return typeof value === 'string' && RECORD_ID_PATTERN.test(value);
}

export function newTempId(prefix = 'ObsId') {
    return `${prefix}-${Math.random().toString(36).substring(2, 8)}${Date.now()}`;
}

// A row not yet saved: Id is the temporary client Id until the save maps it to the record Id
export function newRow() {
    const id = newTempId();
    return { Id: id, key: id, Observations_from_Previous_Visit__c: false, X2x_Penalty_Applicable__c: false };
}

export function formatObservationData(observations, observationMaster) {
    const grouped = {};

    (Array.isArray(observations) ? observations : []).forEach(obs => {
        const link = obs?.ContentDocumentLinks?.[0];
        const contentDocId = link?.ContentDocumentId;

        if (!contentDocId) return;

        if (!grouped[contentDocId]) {
            grouped[contentDocId] = buildGroup(
                contentDocId,
                contentDocId,
                link.ContentDocument?.LatestPublishedVersion?.Title || '',
                link.ContentDocument?.LatestPublishedVersion?.VersionDataUrl || null
            );
        }

        const { ContentDocumentLinks, ...obsFields } = obs;
        grouped[contentDocId].Observations.push(decorateRow(obsFields, observationMaster));
    });

    return withDisplayHints(Object.values(grouped));
}

/**
 * key identifies the image on screen and never changes; ContentDocumentId is the temporary key of a new image
 * until its save returns the real Id.
 */
export function buildGroup(key, contentDocumentId, title, versionDataUrl) {
    return { key, ContentDocumentId: contentDocumentId, Title: title, VersionDataUrl: versionDataUrl, isNew: false, Observations: [] };
}

/**
 * Adds the UI-only properties (key, options, tags, labels) a row needs.
 * key identifies the row on screen and never changes, so swapping a temporary Id for the record Id
 * after a save does not re-render the row (no lost focus or closed dropdown while the user is editing).
 */
export function decorateRow(row, observationMaster) {
    row.key = row.key ?? row.Id;

    const categoryObj = observationMaster?.[row.Category__c];
    const subCategoryObj = categoryObj?.[row.Sub_Category__c];

    row.RepeatedLabel = row.X2x_Penalty_Applicable__c ? 'Repeated' : 'Repeated?';
    row.subCategoryOptions = toOptions(categoryObj);
    row.observationOptions = toOptions(subCategoryObj);
    row.tags = subCategoryObj?.[row.Observation_Non_Compliance__c]?.tags || [];
    return row;
}

export function toOptions(obj) {
    return obj ? Object.keys(obj).map(key => ({ label: key, value: key })) : [];
}

export function withDisplayHints(data) {
    data.forEach(group => {
        const lastIndex = group.Observations.length - 1;
        group.Observations.forEach((obs, index) => {
            obs.displayBreak = index < lastIndex;
        });
    });
    return data;
}

// '' and undefined count as empty, so clearing a field back to blank is not a change
const normalize = value => (value === '' || value === undefined ? null : value);

export function snapshotRow(row) {
    const snapshot = {};
    ROW_FIELDS.forEach(field => {
        snapshot[field] = normalize(row[field]);
    });
    return snapshot;
}

// Snapshots are kept by row key
export function snapshotAll(data) {
    const snapshots = {};
    data.forEach(group => group.Observations.forEach(row => {
        snapshots[row.key] = snapshotRow(row);
    }));
    return snapshots;
}

export function isRowDirty(row, snapshots) {
    const saved = snapshots[row.key];
    return !saved || ROW_FIELDS.some(field => normalize(row[field]) !== saved[field]);
}

export function hasDirtyRows(data, snapshots) {
    return data.some(group => group.isNew || group.Observations.some(row => isRowDirty(row, snapshots)));
}

function toRecordPayload(row) {
    return {
        Id: row.Id,
        category: row.Category__c ?? '',
        subCategory: row.Sub_Category__c ?? '',
        observationNonCompliance: row.Observation_Non_Compliance__c ?? '',
        agentComments: row.Agent_Comments__c ?? '',
        repeated: row.Observations_from_Previous_Visit__c ?? false,
        x2xPenaltyApplicable: row.X2x_Penalty_Applicable__c ?? false,
        observationsDisplayOrder: row.Observations_Display_Order__c ?? null
    };
}

/**
 * Payload for ZC_Helper.saveObservations containing only new or changed rows of images that are already saved.
 * Also returns the snapshot of each sent row, so edits made while the request runs stay unsaved.
 */
export function buildSavePayload(data, snapshots) {
    const groups = [];
    const sent = [];

    data.forEach(group => {
        if (group.isNew) return;

        const rows = group.Observations.filter(row => isRowDirty(row, snapshots));
        if (!rows.length) return;

        groups.push({ ContentDocumentId: group.ContentDocumentId, Observations: rows.map(toRecordPayload) });
        rows.forEach(row => sent.push({ key: row.key, id: row.Id, snapshot: snapshotRow(row) }));
    });

    return { groups, sent };
}

// Payload for ZC_Helper.saveImageObservations: every row of one new image (no image data, that is sent separately)
export function buildImagePayload(group) {
    const rows = group.Observations;
    return {
        payload: { ContentDocumentId: group.ContentDocumentId, Observations: rows.map(toRecordPayload) },
        sent: rows.map(row => ({ key: row.key, id: row.Id, snapshot: snapshotRow(row) }))
    };
}

// Assign one stable visit-wide position in the current displayed group/row order before saving.
export function assignDisplayOrder(data) {
    let order = 1;
    data.forEach(group => group.Observations.forEach(row => {
        row.Observations_Display_Order__c = order++;
    }));
}

export function buildRemarks(data) {
    let remarks = '';
    let count = 1;

    data.forEach(group => group.Observations.forEach(obs => {
        if (obs.Agent_Comments__c) {
            remarks += `${count}. ${obs.Agent_Comments__c}\n`;
            count++;
        }
    }));

    return remarks;
}

export function reduceError(error) {
    return error?.body?.message || error?.message || 'Unknown error';
}


/**
 * Compresses a photo to at most TARGET_IMAGE_BYTES. The quality is found with a binary search
 * (a few passes) instead of stepping down 1% at a time, which was very slow on iPad.
 */
export async function compressImage(file) {
    const first = await processImage(file, { ...COMPRESS_OPTIONS, compressionQuality: 0.9 });
    if (first.size <= TARGET_IMAGE_BYTES) return first;

    let low = 0.1;
    let high = 0.9;
    let best = null;

    for (let step = 0; step < QUALITY_SEARCH_STEPS; step++) {
        const quality = (low + high) / 2;
        // eslint-disable-next-line no-await-in-loop
        const candidate = await processImage(file, { ...COMPRESS_OPTIONS, compressionQuality: quality });
        if (candidate.size <= TARGET_IMAGE_BYTES) {
            best = candidate;
            low = quality;
        }
        else {
            high = quality;
        }
    }

    return best ?? processImage(file, { ...COMPRESS_OPTIONS, compressionQuality: 0.1 });
}

// Small data URL for the on-screen preview
export async function createPreview(blob) {
    const preview = await processImage(blob, PREVIEW_OPTIONS);
    return readAsDataUrl(preview);
}

// Base64 of the compressed image, created only when the image is being saved
export async function blobToBase64(blob) {
    const dataUrl = await readAsDataUrl(blob);
    return dataUrl.substring(dataUrl.indexOf(',') + 1);
}

function readAsDataUrl(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
}


// Gap between starting two calls; only long enough for each call to leave as its own request
const CALL_START_SPACING_MS = 25;

/**
 * Starts every task straight away, without waiting for any response, and resolves with one { ok, value | error }
 * per task once all have finished. The starts are spaced a few milliseconds apart so the Apex calls are sent as
 * separate requests that run in parallel, instead of being combined into one large request.
 */
export function fireInParallel(tasks) {
    return Promise.all(tasks.map((task, index) => new Promise(resolve => {
        setTimeout(() => {
            Promise.resolve()
                .then(task)
                .then(value => resolve({ ok: true, value }), error => resolve({ ok: false, error }));
        }, index * CALL_START_SPACING_MS);
    })));
}