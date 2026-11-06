/**
 * ZC_Helper
 * ----------------------------------------------------------------------------
 * Purpose:
 *   Server-side helper for Construction Compliance.
 *
 * Version History:
 * Version | Last Modified Date |      Last Modified By      |                          Description                         |
 * --------------------------------------------------------------------------------------------------------------------------
 * 1.0     | 15-12-2025         | Suriya S                   | Initial version                                              |
 * --------------------------------------------------------------------------------------------------------------------------
 */
public with sharing class ZC_Helper {
    
    private static BusinessHours defaultBH = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];

    public static Date getBusinessDays(Integer numberOfDaysToAdd, Datetime dateTimeValue) {
        Long milliSecondsToAdd = numberOfDaysToAdd * (3600000L * 24L);
        Datetime nextStart = BusinessHours.add(defaultBH.Id, dateTimeValue, milliSecondsToAdd);
        return nextStart.date();
    }


    @AuraEnabled(cacheable = true)
    public static List<ZC_Visit__c> getVisitAndRelated(){
        try {
            return [
                SELECT Id, Name, Building_Number__c, CCEmails__c, Comments__c, Completion__c, Consultant_Email__c, Consultant_Mobile__c, Consultant_Name__c, CVR_Created__c,
                Consultant_Project_Manager_Email__c, Consultant_Project_Manager_Mobile__c, Consultant_Project_Manager__c, Contractor_Email__c, Contractor_Mobile__c, Contractor_Name__c, 
                Contractor_Project_Manager_Email__c, Contractor_Project_Manager_Mobile__c, Contractor_Project_Manager__c, Date_of_Visit__c, Documentation__c, Expected_Completion_Date__c, 
                Follow_up__c, Is_Unregistered_Consultant__c, Is_Unregistered_Contractor__c, Is_Villa_Visit__c, Latest_Issued_Notice__c, Main_Image_Name__c, STS_Project__r.Project_Completion__c,
                Man_Power__c, No_Observation__c, Number_of_Building__c, Number_of_Observation__c, Permits__c, Plot__c, Project_Detail__c, Project_Height__c, Remarks__c, Reviewer__c, Risk_Status__c, 
                STS_Project__c, Site_Situation__c, Stage_of_work__c, Start_Date__c, Suspended_Activities__c, Suspension__c, Total_Risk_Factor__c, Unreg_Consultant_Email__c, Unreg_Consultant_Mobile__c, 
                Unreg_Consultant_Name__c, Unreg_Contractor_Email__c, Unreg_Contractor_Mobile__c, Unreg_Contractor_Name__c, Visit_Type__c, CVR_Saved__c, CreatedById, CreatedBy.Name, Status__c,
                Status__r.Name, Assigned_Agent__c, Assigned_Agent__r.Name, Assigned_Agent__r.Email, Main_Consultant__c, Main_Consultant__r.Name, Main_Consultant__r.Email__c, Main_Contractor__c, 
                Main_Contractor__r.Name, Main_Contractor__r.Email__c, STS_Project__r.Name, STS_Project__r.Contractor__c, STS_Project__r.Project_Status__c, 
                STS_Project__r.Enabling_Contractor__c, Plot__r.Name, Plot__r.Height__c, Plot__r.Master_Project__c, Plot__r.Visit_Identifier__c, Plot__r.Master_Project_Id__c, 
                Plot__r.No_Of_Active_HSE_Officers__c, Plot__r.Land__r.Name, (
                    SELECT Id, LinkedEntityId, ContentDocumentId, ContentDocument.LatestPublishedVersion.Id, ContentDocument.LatestPublishedVersion.Title, ContentDocument.LatestPublishedVersion.VersionDataUrl
                    FROM ContentDocumentLinks
                )
                FROM ZC_Visit__c
                WHERE Assigned_Agent__c =: UserInfo.getUserId() AND Status__r.Name IN ('Visit Assigned', 'Officer Visit Follow-up')
            ];
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }


    @AuraEnabled(cacheable = true)
    public static List<STS_Project__C> getPreviousVisitAndProjectConditions(){
        try {
            return [
                SELECT Id, Name, (
                    SELECT Id, Name, Contractor_Project_Manager__c, Contractor_Project_Manager_Email__c, Contractor_Project_Manager_Mobile__c, Consultant_Project_Manager__c, 
                    Consultant_Project_Manager_Email__c, Consultant_Project_Manager_Mobile__c, Completion__c, Expected_Completion_Date__c, Site_Situation__c, Status__c, Status__r.Name, (
                        SELECT Id, Observation_Non_Compliance__c, Observations_from_Previous_Visit__c, ZC_Visit__c, Sub_Category__c, Category__c, Status__c, Agent_Comments__c
                        FROM ZC_Observations__r
                    )
                    FROM Visit_Reviews__r 
                    WHERE Status__r.Name != 'Visit Assigned'
                    	AND Status__r.Name != 'Un Assigned'
                ), (
                    SELECT Id, Name, Project_Condition__c, Department__c, Time_Frame_Date__c, Type__c, Status__c, Added_Date__c, Visit__c, Visit__r.Name
                    FROM STS_Project_Conditions__r
                    WHERE Is_Active__c = true
                    AND Department__c = 'Construction Compliance'
                )
                FROM STS_Project__c
                WHERE Id IN (
                    SELECT STS_Project__c
                    FROM ZC_Visit__c
                    WHERE Assigned_Agent__c = :UserInfo.getUserId()
                    AND Status__r.Name IN ('Visit Assigned', 'Officer Visit Follow-up')
                )
            ];
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }


    @AuraEnabled(cacheable = true)
    public static List<ZC_Observation__c> getObservations(String visitId, String dummyTimeStampForWireRefresh){
        try {
            return [
                SELECT Id, Observation_Non_Compliance__c, ZC_Visit__r.Main_Consultant__c,ZC_Visit__r.Main_Contractor__c, Observations_from_Previous_Visit__c, ZC_Visit__c, Sub_Category__c, Category__c, Status__c, Agent_Comments__c, X2x_Penalty_Applicable__c, Observations_Display_Order__c, ZC_Visit__r.Status__r.Name, Review_Comments__c, Team_Lead_Comments__c, (
                    SELECT Id, LinkedEntityId, ContentDocumentId, ContentDocument.LatestPublishedVersion.Id, ContentDocument.LatestPublishedVersion.Title, ContentDocument.LatestPublishedVersion.VersionDataUrl
                    FROM ContentDocumentLinks
                )
                FROM ZC_Observation__c 
                WHERE ZC_Visit__c = :visitId
                ORDER BY Observations_Display_Order__c ASC NULLS LAST, CreatedDate ASC, Id ASC
            ];
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }


    @AuraEnabled(cacheable = true)
    public static List<ExpiredPermit> getExpiredPermits(Id projectId) {
        try {
            List<ExpiredPermit> expiredPermits = new List<ExpiredPermit>();
            for (ZC_UtilMethods.PlotPermitsWrapper res : ZC_UtilMethods.getplotpermits(new Set<Id>{projectId}).get(projectId)) {
                if (res.validUpto < System.today()) {
                    ExpiredPermit permit = new ExpiredPermit();
                    permit.permitType = res.appDetailName;
                    permit.validUpto = res.validUpto;
                    permit.remarks = res.submittalTypeName;
                    expiredPermits.add(permit);
                }
            }

            return expiredPermits;
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class ExpiredPermit {
        @AuraEnabled public String permitType;
        @AuraEnabled public Date validUpto;
        @AuraEnabled public String remarks;
    }


    @AuraEnabled(cacheable = true)
    public static List<ZC_Customer_Response__c> getCustomerResponses(String visitId){
        try {
            return [
                SELECT Id, ZC_Observation__c, ZC_Visit__c, Respondent__c, Customer_Response__c, Status__c, format(Response_Date__c), (
                    SELECT Id , FileName__c, Doc_Id__c, portal_token_Id__c FROM Documents__r
                ),(
                    SELECT Id, LinkedEntityId, ContentDocumentId, ContentDocument.LatestPublishedVersion.Id, ContentDocument.LatestPublishedVersion.Title, ContentDocument.LatestPublishedVersion.VersionDataUrl, ContentDocument.FileExtension 
                    FROM ContentDocumentLinks ORDER BY ContentDocument.FileExtension DESC
                )
                FROM ZC_Customer_Response__c 
                WHERE ZC_Visit__c = :visitId
            ];
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage()); 
        }
    }
    

    /**
     * Saves edited rows and new rows added to images that are already saved, then refreshes the Visit remarks.
     * New images are saved separately by saveImageObservations, one call per image.
     */
    @AuraEnabled
    public static SaveResult saveObservations(Id visitId, String jsonData) {
        try {
            SaveResult result = new SaveResult();
            List<ObservationWrapper> groups = String.isBlank(jsonData) ? new List<ObservationWrapper>() : (List<ObservationWrapper>) JSON.deserialize(jsonData, List<ObservationWrapper>.class);
            List<ZC_Observation__c> observations = new List<ZC_Observation__c>();
            List<Id> linkDocumentIds = new List<Id>();   // index-aligned with observations, null = already linked
            List<String> tempIds = new List<String>();   // index-aligned with observations, client Id of rows being inserted
            List<String> clientIds = new List<String>(); // index-aligned with observations for returning saved display order

            for (ObservationWrapper grp : groups) {
                if (grp.Observations == null) continue;
                Id documentId = toId(grp.ContentDocumentId);

                for (ObservationRecord record : grp.Observations) {
                    ZC_Observation__c obs = mapObsFields(record);
                    obs.Id = toId(record.Id);
                    obs.ZC_Visit__c = visitId;
                    observations.add(obs);
                    linkDocumentIds.add(obs.Id == null ? documentId : null);
                    tempIds.add(obs.Id == null ? record.Id : null);
                    clientIds.add(record.Id);
                }
            }

            if (!observations.isEmpty()) {
                upsert observations;

                List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                for (Integer i = 0; i < observations.size(); i++) {
                    if (tempIds[i] != null) result.idMap.put(tempIds[i], observations[i].Id);
                    result.observationsDisplayOrderMap.put(clientIds[i], observations[i].Observations_Display_Order__c);
                    if (linkDocumentIds[i] != null) links.add(newLink(linkDocumentIds[i], observations[i].Id));
                }
                if (!links.isEmpty()) insert links;
            }

            refreshRemarks(visitId);
            return result;
        }
        catch (Exception e) {
            throw toAuraException('Error saving the observations: ', e);
        }
    }


    /**
     * Saves one new image with its rows in a single transaction: the rows are inserted, the compressed image is stored
     * as a file published to the first row and linked to the others. If anything fails nothing is kept, so a retry
     * cannot create duplicates. Remarks are refreshed by the saveObservations call that follows the image calls.
     */
    @AuraEnabled
    public static SaveResult saveImageObservations(Id visitId, String jsonData, String fileName, String fileContent) {
        try {
            SaveResult result = new SaveResult();
            ObservationWrapper grp = String.isBlank(jsonData) ? null : (ObservationWrapper) JSON.deserialize(jsonData, ObservationWrapper.class);
            if (grp == null || grp.Observations == null || grp.Observations.isEmpty() || String.isBlank(fileContent)) return result;

            List<ZC_Observation__c> observations = new List<ZC_Observation__c>();
            for (ObservationRecord record : grp.Observations) {
                ZC_Observation__c obs = mapObsFields(record);
                obs.ZC_Visit__c = visitId;
                observations.add(obs);
            }
            insert observations;

            for (Integer i = 0; i < observations.size(); i++) {
                result.idMap.put(grp.Observations[i].Id, observations[i].Id);
                result.observationsDisplayOrderMap.put(grp.Observations[i].Id, observations[i].Observations_Display_Order__c);
            }

            Id firstObservationId = observations[0].Id;
            ContentVersion version = new ContentVersion(
                VersionData = EncodingUtil.base64Decode(fileContent),
                PathOnClient = fileName,
                Title = fileName,
                RelatedId__c = firstObservationId,
                FirstPublishLocationId = firstObservationId,
                Status__c = 'Draft',
                Have_To_Prepopulate__c = !Test.isRunningTest(),
                ZP_Integrate__c = true
            );
            insert version;
            version = [SELECT Id, ContentDocumentId, Title, VersionDataUrl FROM ContentVersion WHERE Id = :version.Id];

            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Integer i = 1; i < observations.size(); i++) {
                links.add(newLink(version.ContentDocumentId, observations[i].Id));
            }
            if (!links.isEmpty()) insert links;

            UploadedImage image = new UploadedImage();
            image.observationId = firstObservationId;
            image.contentDocumentId = version.ContentDocumentId;
            image.contentVersionId = version.Id;
            image.title = version.Title;
            image.versionDataUrl = version.VersionDataUrl;
            result.uploads.add(image);

            return result;
        }
        catch (Exception e) {
            throw toAuraException('Error saving the image ' + fileName + ': ', e);
        }
    }


    /**
     * Deletes observations removed on screen. The image is deleted only when the client says its group is now empty
     * and no other observation still uses it.
     */
    @AuraEnabled
    public static void removeObservations(Id visitId, List<Id> observationIds, Id contentDocumentId) {
        try {
            if (observationIds != null && !observationIds.isEmpty()) {
                delete [SELECT Id FROM ZC_Observation__c WHERE Id IN :observationIds];
            }

            if (contentDocumentId != null) {
                Boolean stillUsed = false;
                for (ContentDocumentLink link : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :contentDocumentId]) {
                    if (link.LinkedEntityId.getSObjectType() == ZC_Observation__c.SObjectType) {
                        stillUsed = true;
                        break;
                    }
                }
                if (!stillUsed) delete new ContentDocument(Id = contentDocumentId);
            }

            if (visitId != null) refreshRemarks(visitId);
        }
        catch (Exception e) {
            throw toAuraException('Error removing the observation: ', e);
        }
    }


    // The Visit is written only when the remarks really change
    private static void refreshRemarks(Id visitId) {
        ZC_Visit__c visit = [SELECT Remarks__c, (SELECT Agent_Comments__c FROM ZC_Observations__r ORDER BY Observations_Display_Order__c ASC NULLS LAST, CreatedDate ASC, Id ASC) FROM ZC_Visit__c WHERE Id = :visitId];
        String remarks = '';
        Integer count = 1;
        for (ZC_Observation__c obs : visit.ZC_Observations__r) {
            if (String.isNotBlank(obs.Agent_Comments__c)) {
                remarks += count + '. ' + obs.Agent_Comments__c + '\n';
                count++;
            }
        }
        if ((visit.Remarks__c ?? '') != remarks) {
            update new ZC_Visit__c(Id = visitId, Remarks__c = remarks);
        }
    }

    private static ContentDocumentLink newLink(Id documentId, Id observationId) {
        return new ContentDocumentLink(ContentDocumentId = documentId, LinkedEntityId = observationId, ShareType = 'V', Visibility = 'AllUsers');
    }

    private static AuraHandledException toAuraException(String prefix, Exception e) {
        System.debug(LoggingLevel.ERROR, prefix + e.getMessage() + '\n' + e.getStackTraceString());
        AuraHandledException ex = new AuraHandledException(prefix + e.getMessage());
        ex.setMessage(prefix + e.getMessage());
        return ex;
    }

    public class SaveResult {
        @AuraEnabled public Map<String, Id> idMap = new Map<String, Id>();   // client temp Id -> new observation Id
        @AuraEnabled public Map<String, Decimal> observationsDisplayOrderMap = new Map<String, Decimal>(); // client Id -> saved order
        @AuraEnabled public List<UploadedImage> uploads = new List<UploadedImage>();
    }

    public class UploadedImage {
        @AuraEnabled public Id observationId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String versionDataUrl;
    }

    private static Id toId(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        }
        catch (StringException e) {
            return null;
        }
    }

    private static ZC_Observation__c mapObsFields(ObservationRecord record){
        ZC_Observation__c obs = new ZC_Observation__c();
        obs.Observation_Non_Compliance__c = record.observationNonCompliance;
        obs.ZC_Visit__c = record.visitId;
        obs.Sub_Category__c = record.subCategory;
        obs.Category__c = record.category;
        obs.Agent_Comments__c = record.agentComments;
        obs.Observations_from_Previous_Visit__c = record.repeated == true;
        obs.X2x_Penalty_Applicable__c = record.x2xPenaltyApplicable == true;
        obs.Observations_Display_Order__c = record.observationsDisplayOrder;
        return obs;
    }


    @AuraEnabled(cacheable=true)
    public static Boolean isCurrentUserOwner(String recordId) {
        try {
            Id currentUserId = UserInfo.getUserId();

            SObject record = Database.query('SELECT OwnerId FROM ' + Id.valueOf(recordId).getSObjectType().getDescribe().getName() + ' WHERE Id = :recordId LIMIT 1');

            Id ownerId = (Id) record.get('OwnerId');

            if (ownerId == currentUserId) {
                return true;
            }

            if (ownerId.getSObjectType() == Group.SObjectType) {
                return [SELECT COUNT() FROM GroupMember WHERE GroupId = :ownerId AND UserOrGroupId = :currentUserId] > 0;
            }

            return false;
        }
        catch (Exception e) {
            System.debug('Ownership check failed: ' + e.getMessage());
            return false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isCurrentUserInTLQueue() {
        return [
            SELECT COUNT()
            FROM GroupMember
            WHERE Group.DeveloperName = 'ZC_Team_Lead_Pool'
                AND Group.Type = 'Queue'
                AND UserOrGroupId = :UserInfo.getUserId()
        ] > 0;
    }


    public class ObservationWrapper {
        @AuraEnabled public String ContentDocumentId;
        @AuraEnabled public List<ObservationRecord> Observations;
    }

    public class ObservationRecord {
        @AuraEnabled public String Id;
        @AuraEnabled public String observationNonCompliance;
        @AuraEnabled public String visitId;
        @AuraEnabled public String subCategory;
        @AuraEnabled public String category;
        @AuraEnabled public String agentComments;
        @AuraEnabled public Boolean repeated;
        @AuraEnabled public Boolean x2xPenaltyApplicable;
        @AuraEnabled public Decimal observationsDisplayOrder;
    }


    @AuraEnabled
    public static Map<String, Object> generateCVRDataForPDFPreview(String visitId) {
        if (String.isBlank(visitId)) {
            throw new AuraHandledException('Error in CVR Generation. Didn\'t receive Visit Id in apex.');
        }
        try {
            return new Map<String, Object>{
                'vap' => ZCObservationMatrixHelper.analyze(new List<Id>{ visitId }, true)
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<Id, Map<String, List<Object>>> submitVisit(String visitId, Boolean isNoObservation, String noObsJustification){
        Savepoint sp = Database.setSavepoint();
        Map<Id, Map<String, List<Object>>> result = new Map<Id, Map<String, List<Object>>>();
        try {
            ZC_Visit__c visit = [SELECT Id, Name, Plot__c, Is_Villa_Visit__c, Site_Situation__c, Stage_of_work__c, No_Observation__c, 
                                        Visit_Type__c, Follow_up__c, Assigned_Agent__c, Date_of_Visit__c, CCEmails__c, Target_Date__c, 
                                        Customer_Meeting_Date__c, Compliance_Notice1__c, Compliance_Notice2__c, Resolution_Notice__c, 
                                        SWO_Full__c, SWO_Partial__c, Consultant_Project_Manager_Email__c, Contractor_Project_Manager_Email__c, 
                                        Unreg_Consultant_Email__c, Unreg_Contractor_Email__c, Main_Contractor__c, Main_Consultant__c, 
                                        Assigned_Agent__r.Email, Plot__r.Name, Plot__r.Master_Project__c, Main_Consultant__r.Email__c, 
                                        Main_Consultant__r.Name, Main_Contractor__r.Email__c, Main_Contractor__r.Name, STS_Project__c, 
                                        STS_Project__r.Site_Status__c, STS_Project__r.Project_Status__c, STS_Project__r.Super_Structure_Date__c, 
                                        STS_Project__r.Project_Sub_Status__c, STS_Project__r.No_of_Visits_After_completed_with_UL__c, 
                                        STS_Project__r.Last_Visit_Date__c, STS_Project__r.Last_Scheduled_Visit_Date__c, STS_Project__r.RecordType.Name, 
                                        STS_Project__r.Project_Inactive_Date__c, STS_Project__r.Final_Visit_Completed__c, Unreg_Consultant_Mobile__c, 
                                        Unreg_Contractor_Mobile__c,Completion__c
                                    FROM ZC_Visit__c 
                                    WHERE Id =: visitId 
                                    LIMIT 1
                                ];
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF content');
            }
            else {
            PageReference pdfPage = Page.ZC_CVRAsPDF;
            pdfPage.getParameters().put('VisitId', visitId);
                pdfBlob = pdfPage.getContentAsPDF();
            }
            ContentVersion cv = new ContentVersion();
            cv.VersionData = pdfBlob;
            cv.PathOnClient = 'CVR-' + visit.Name + '.pdf';
            cv.Title = 'CVR-' + visit.Name + '.pdf';
            cv.RelatedId__c = visitId;
            cv.FirstPublishLocationId = visitId;
            cv.Status__c = 'Draft';
            cv.Have_To_Prepopulate__c = !Test.isRunningTest();
            cv.Document_Type__c = 'CVR';
            cv.ZP_Integrate__c = true;
            insert cv;

            Map<String, String> visitStatusesMap = new Map<String, String>();
            for(ZC_Status__c status : [SELECT Id, Name FROM ZC_Status__c]){
                visitStatusesMap.put(status.Name, status.Id);
            }

            List<ZC_NotificationsHelper.NotificationConfig> notifications = new List<ZC_NotificationsHelper.NotificationConfig>();
            List<ZC_Visit__c> visitList = new List<ZC_Visit__c>();
            
            visit.Id = visitId;
            visit.CVR_Created__c = true;
            visit.OwnerId = ZC_StaticVariablesUtil.customerPoolQId;
            visit.Status__c = visitStatusesMap.get(ZC_StaticVariablesUtil.statusIdAwaitingCustomerResponse);
            visit.Reviewer__c = 'Customer';
            visit.CVR_Issued_Date__c = System.today();
            visit.Date_of_Visit__c = System.today();
            if (isNoObservation) {
                visit.No_Observation__c = true;
                visit.Close_Comments__c = noObsJustification;
                visit.Visit_Closed_Date__c = System.today();
                visit.Status__c = visitStatusesMap.get(ZC_StaticVariablesUtil.VisitClosed);
            }
            else {
                visit.Target_Date__c = ZC_UtilMethods.getBusinessdays(5, System.now());
                Map<Id, ZCObservationMatrixHelper.VisitActionPlan> res = ZCObservationMatrixHelper.analyze(new List<Id>{visitId}, true);
                visit.Risk_Factor__c = res.get(visitId).visitRiskRating;
                if (res != null && (res.get(visitId)?.swo?.decision != null || res.get(visitId)?.consultantFineDecisions?.size() > 0 || res.get(visitId)?.contractorFineDecisions?.size() > 0)) {
                    result = ZCObservationMatrixHelper.createFurtherActions(res, true);
                    
                    if (res.get(visitId).swo.decision == 'Partial') {
                        visit.Suspension__c = 'Partial Suspension';
                        visit.SWO_Partial__c = system.today();
                        visit.Latest_Issued_Notice__c = 'SWO-Partial';
                    }
                    else if (res.get(visitId).swo.decision == 'Full') {
                        visit.Suspension__c = 'Full Suspension';
                        visit.SWO_Full__c = system.today();
                        visit.Latest_Issued_Notice__c = 'SWO-Full';
                    }
                    else {
                        visit.Latest_Issued_Notice__c = 'CVR';
                    }
                }
                notifications.add(new ZC_NotificationsHelper.NotificationConfig(visit.Id, null, null, 'Compliance Observation Resolution', 'Consultant', true));
                notifications.add(new ZC_NotificationsHelper.NotificationConfig(visit.Id, null, null, 'Compliance Observation Resolution', 'Contractor', true));
            }
            visitList.add(visit);

            upsert visitList;

            if (visit.STS_Project__c != null) {
                STS_Project__c prj = new STS_Project__c();
                prj.Id = visit.STS_Project__c;
                prj.Site_Status__c = visit.Site_Situation__c;
                prj.Last_Visit_Date__c = System.today();
                prj.Project_Completion__c=visit.Completion__c;
                if(visit.STS_Project__r.Super_Structure_Date__c == null && new set<string>{'Finishing','Super Structure G+1','Super Structure 2-12','Super Structure Above 12','Completed with comments'}.contains(visit.Stage_of_work__c)) {
                    prj.Super_Structure_Date__c = System.today();
                    prj.Yardi_Integration_Status__c = 'Ready';
                }
                if(visit.Visit_Type__c == 'Scheduled') {
                    prj.Last_Scheduled_Visit_Date__c = System.today();
                }                
                if(visit.STS_Project__r.Project_Inactive_Date__c == null && (visit.Site_Situation__c == 'Inactive' || visit.Site_Situation__c == 'Not Started')) {
                    prj.Project_Inactive_Date__c = System.today();
                }
                else if(visit.STS_Project__r.Project_Inactive_Date__c <> null && (visit.Site_Situation__c <> 'Inactive' && visit.Site_Situation__c <> 'Not Started')) {
                    prj.Project_Inactive_Date__c = null;
                }
                update prj;
                if(visit.Is_Villa_Visit__c) {
                    database.executeBatch(new ZC_BatchUpdateSiteStatusOnPrjandPlot(visit));
                }
            }
            if (visit.Plot__c != null && String.isNotBlank(visit.Site_Situation__c)) {
                MP_Plot__c plt = new MP_Plot__c( Id = visit.Plot__c, Site_Status__c = visit.Site_Situation__c );
                update plt;
            }
            
            if (!notifications.isEmpty()) {
                ZC_NotificationsHelper.send(notifications);
            }
            
            return result;
        }
        catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }


    @AuraEnabled
    public static Id submitProjectConditionClearance(Id projectConditionId, String justification, String filesJson){
        Savepoint sp = Database.setSavepoint();
        try {
            if (projectConditionId == null) return null;
            
            if (String.isBlank(justification)) {
                throw new AuraHandledException('Justification is required.');
            }

            List<FileWrapperDTO> files = new List<FileWrapperDTO>();
            if (!String.isBlank(filesJson)) {
                files = (List<FileWrapperDTO>) JSON.deserialize(filesJson, List<FileWrapperDTO>.class);
            }

            STS_Project_Condition__c cond = [
                SELECT Id, STS_Project__c, Approval_Department__c, Project_Condition__c, Remarks__c, Time_Frame__c
                FROM STS_Project_Condition__c
                WHERE Id = :projectConditionId
                LIMIT 1
            ];

            if (cond == null || cond.STS_Project__c == null) {
                return null;
            }

            PC_Clearance_Request__c req = new PC_Clearance_Request__c();
            req.STS_Project__c = cond.STS_Project__c;
            req.STS_Project_Condition__c = projectConditionId;
            req.STS_Approval_Department__c = cond.Approval_Department__c;
            req.Action__c = 'PC Clearance';
            req.Justification__c = justification;
            req.SLA_Start_Date__c = System.now();
            req.SLA_Follow_Up_Date__c = STS_Utility.getNextBusinessDay(System.now(), 18);
            req.Project_Condition__c = cond.Project_Condition__c;
            req.Remarks__c = cond.Remarks__c;
            req.Time_Frame__c = cond.Time_Frame__c;
            req.Status__c = 'Under Department Review';

            Database.SaveResult sr = Database.insert(req, false);
            if (!sr.isSuccess()) {
                return null;
            }
            Id requestId = sr.getId();

            if (!files.isEmpty()) {
                List<ContentVersion> versions = new List<ContentVersion>();
                for (FileWrapperDTO f : files) {
                    if (f == null || String.isBlank(f.content)) continue;
                    ContentVersion cv = new ContentVersion();
                    cv.VersionData = EncodingUtil.base64Decode(f.content);
                    cv.PathOnClient = f.name;
                    cv.Title = (f.name != null && f.name.contains('.')) ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
                    cv.RelatedId__c = projectConditionId;
                    cv.FirstPublishLocationId = projectConditionId;
                    cv.Status__c = 'Draft';
                    cv.Have_To_Prepopulate__c = !Test.isRunningTest();
                    // cv.Document_Type__c = (f.type != null) ? f.type : 'document';
                    cv.ZP_Integrate__c = true;
                    versions.add(cv);
                }

                if (!versions.isEmpty()) {
                    Database.insert(versions, false);

                    Map<Id, Id> verToDoc = new Map<Id, Id>();
                    for (ContentVersion v : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :versions]) {
                        verToDoc.put(v.Id, v.ContentDocumentId);
                    }

                    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                    for (ContentVersion v : versions) {
                        Id cdocId = verToDoc.get(v.Id);
                        if (cdocId == null) continue;
                        links.add(new ContentDocumentLink(ContentDocumentId = cdocId, LinkedEntityId = projectConditionId, ShareType = 'V', Visibility = 'AllUsers'));
                    }

                    if (!links.isEmpty()) {
                        Database.insert(links, false);
                    }
                }
            }

            STS_Project_Condition__c updateCond = new STS_Project_Condition__c(Id = cond.Id, Status__c = 'Pending for Clearance', Clearance_Request_Date__c = System.now());
            Database.update(updateCond, false);
            
            Approval.ProcessSubmitRequest approvalReq = new Approval.ProcessSubmitRequest();
            approvalReq.setObjectId(requestId);
            approvalReq.setProcessDefinitionNameOrId('STS_Project_Conditions_Req_Process');
            approvalReq.setComments(null);
            
            Approval_Department__c aprDept = null;
            if (cond.Approval_Department__c != null) {
                aprDept = [SELECT Id, Queue_Id__c FROM Approval_Department__c WHERE Id = :cond.Approval_Department__c LIMIT 1];
            }
            
            if (aprDept != null && aprDept.Queue_Id__c != null) {
                approvalReq.setNextApproverIds(new Id[]{aprDept.Queue_Id__c});
            }
            else {
                Database.rollback(sp);
                throw new AuraHandledException('Unable to submit PC Clearance Request for approval: Approval Department or Queue not properly configured.');
            }
            
            Approval.ProcessResult[] results = Approval.process(new List<Approval.ProcessSubmitRequest>{approvalReq});
            
            return requestId;
        }
        catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Unable to submit PC Clearance Request for approval. Error Message: ' + e.getMessage());
        }
    }

    public class FileWrapperDTO {
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String content;
    }
    

    @AuraEnabled
    public static Map<Id, Map<String, List<Object>>> submitVisitFromDetailsPage(String visitId, Boolean isReturn){
        Savepoint sp = Database.setSavepoint();
        try {
            ZC_Visit__c visit = [   SELECT Id, Name,Not_Satisfactory_Response__c, Plot__c, Is_Villa_Visit__c, Site_Situation__c, Stage_of_work__c, No_Observation__c, Visit_Type__c, Status__r.Name,
                                        STS_Project__c, STS_Project__r.Site_Status__c, STS_Project__r.Project_Status__c, Follow_up__c, Assigned_Agent__c,
                                        STS_Project__r.Super_Structure_Date__c, STS_Project__r.Project_Sub_Status__c, STS_Project__r.No_of_Visits_After_completed_with_UL__c, 
                                        STS_Project__r.Last_Visit_Date__c, STS_Project__r.Last_Scheduled_Visit_Date__c, STS_Project__r.RecordType.Name, STS_Project__r.Project_Inactive_Date__c, 
                                        STS_Project__r.Final_Visit_Completed__c, CCEmails__c, Main_Contractor__c, Main_Consultant__c, (
                                            SELECT Id FROM ZC_Observations__r WHERE Status__c = 'Open'
                                        ), (
                                            SELECT Id FROM Visit_Reviews__r
                                        )
                                    FROM ZC_Visit__c 
                                    WHERE Id =: visitId 
                                    LIMIT 1
                                ];

            Map<String, String> visitStatusesMap = new Map<String, String>();
            for(ZC_Status__c status : [SELECT Id, Name FROM ZC_Status__c]){
                visitStatusesMap.put(status.Name, status.Id);
            }

            List<ZC_Visit__c> visitList = new List<ZC_Visit__c>();

            if (isReturn == true) {
                visit.Status__c = visitStatusesMap.get('Officer Review CR');
                visit.Reviewer__c = 'Agent';
                // visit.Target_Date__c = ZC_UtilMethods.getBusinessdays(2, System.now());
                visit.OwnerId = visit.Assigned_Agent__c;
                update visit;
                return null;
            }
            
            Map<Id, Map<String, List<Object>>> result = new Map<Id, Map<String, List<Object>>>();
            Map<Id, ZCObservationMatrixHelper.VisitActionPlan> res = ZCObservationMatrixHelper.analyze(new List<Id>{visitId}, false);

            String risk = ZCObservationMatrixHelper.getHighestRiskRating(visitId);
            visit.Risk_Factor__c=risk;
            if ((risk == 'Critical' || risk == 'High') && visit.Status__r.Name == 'Officer Review CR') {
                visit.Status__c = visitStatusesMap.get('Team Lead Review CR');
                visit.Reviewer__c = 'TL';
                // visit.Target_Date__c = ZC_UtilMethods.getBusinessdays(2, System.now());
                visit.OwnerId = System.Label.ZC_TeamLeadQId;
                visitList.add(visit);
            }
            else if ((risk != 'Critical' && risk != 'High') || ((risk == 'Critical' || risk == 'High') && visit.Status__r.Name == 'Team Lead Review CR')) {
                if (res != null) {
                    if (res.get(visitId)?.swo?.decision != null || res.get(visitId)?.consultantFineDecisions?.size() > 0 || res.get(visitId)?.contractorFineDecisions?.size() > 0) {
                        result = ZCObservationMatrixHelper.createFurtherActions(res, false);
                    }
                }
                visit.Status__c = visitStatusesMap.get('Visit Closed');
                visit.Visit_Closed_Date__c = System.today();
                if (visit.ZC_Observations__r.size() > 0) {
                    visit.Not_Satisfactory_Response__c = true;
                }
                visitList.add(visit);
                if (!visit.Follow_up__c && risk == 'Critical' && visit.Visit_Reviews__r.Size() <= 0 && visit.Not_Satisfactory_Response__c) {
                    String visitNumber = createFollowUp(visit.Id, null, null);
                    ZC_Visit__c followUpVisit = [SELECT Id, Name FROM ZC_Visit__c WHERE Name = :visitNumber LIMIT 1];
                    if (followUpVisit != null) {
                        if (!result.containsKey(visit.Id)) {
                            result.put(visit.Id, new Map<String, List<Object>>{
                                'fineRequests' => new List<Object>(),
                                'pcRequests' => new List<Object>(),
                                'blockageRequests' => new List<Object>(),
                                'followupVisit' => new List<Object>()
                            });
                        }
                        if (!result.get(visit.Id).containsKey('followupVisit')) {
                            result.get(visit.Id).put('followupVisit', new List<Object>());
                        }
                        result.get(visit.Id).get('followupVisit').add(new Map<String, String>{
                            'Id' => followUpVisit.Id,
                            'Name' => followUpVisit.Name,
                            'Url' => '/lightning/r/ZC_Visit__c/' + followUpVisit.Id + '/view'
                        });
                    }
                }
            }

            if (!visitList.isEmpty()) {
                upsert visitList;
            }

            return result;
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean checkFollowUpExists(String visitId) {
        return [SELECT COUNT() FROM ZC_Visit__c WHERE Parent_Visit__c = :visitId] > 0;
    }

    @AuraEnabled
    public static String createFollowUp(Id visitId, Id assignedAgentId, String targetDate) {
        ZC_Visit__c visit = [SELECT Id, Plot__c, STS_Project__c, Main_Contractor__c, Main_Consultant__c, Is_Villa_Visit__c, CCEmails__c, Assigned_Agent__c FROM ZC_Visit__c WHERE Id = :visitId LIMIT 1];
        
        Map<String, String> visitStatusesMap = new Map<String, String>();
        for(ZC_Status__c status : [SELECT Id, Name FROM ZC_Status__c]){
            visitStatusesMap.put(status.Name, status.Id);
        }
        
        ZC_Visit__c objVisit = new ZC_Visit__c();
        objVisit.Plot__c = visit.Plot__c;
        objVisit.STS_Project__c = visit.STS_Project__c;
        objVisit.Main_Contractor__c = visit.Main_Contractor__c;
        objVisit.Main_Consultant__c = visit.Main_Consultant__c;
        objVisit.Is_Villa_Visit__c = visit.Is_Villa_Visit__c;
        objVisit.Status__c = visitStatusesMap.get(ZC_StaticVariablesUtil.VisitStatusAssigned);
        objVisit.Visit_Type__c = 'Follow-Up';
        objVisit.CCEmails__c = visit.CCEmails__c;
        objVisit.Target_Date__c = targetDate != null ? Date.valueOf(targetDate) : getBusinessDays(2, System.now());
        objVisit.Assigned_Agent__c = assignedAgentId != null ? assignedAgentId : visit.Assigned_Agent__c;
        objVisit.Follow_up__c = true;
        objVisit.Parent_Visit__c = visit.Id;
        objVisit.OwnerId = assignedAgentId != null ? assignedAgentId : visit.Assigned_Agent__c;
        insert objVisit;

        ZC_Visit__c v = [SELECT Id, Name FROM ZC_Visit__c WHERE Id = :objVisit.Id LIMIT 1];

        return v.Name;
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getQueueMembers() {
        List<GroupMember> members = [SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = 'ZC_Agent_Pool' AND Group.Type = 'Queue'];
        
        Set<Id> userIds = new Set<Id>();
        for (GroupMember gm : members) {
            if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                userIds.add(gm.UserOrGroupId);
            }
        }
        
        if (userIds.isEmpty()) {
            return new List<User>();
        }
        
        return [SELECT Id, Name FROM User WHERE Id IN :userIds AND IsActive = true ORDER BY Name ASC];
    }

    @AuraEnabled
    public static Boolean saveClausesAndJustification(Id parentId, String justification, List<CCRS_Account_Waiver_Clause__c> clausesToUpdate) {
        try {
            if (!clausesToUpdate.isEmpty()) {
                update clausesToUpdate;
            }
    
            update new CCRS_Account_Waiver__c(Id = parentId, Justification__c = justification);

            return true;
        }
        catch (Exception e) {
            System.debug('Error occurred while saving clauses and justification: ' + e.getMessage());
            throw new AuraHandledException('An error occurred while saving the data. ' + e.getMessage());
        }
    }

    
    @AuraEnabled
    public static void generateToken(List<String> recordIds){
        try {
            List<Documents__c> docsToUpdate = new List<Documents__c>();
            for (Documents__c doc : [SELECT Id, portal_token_Id__c FROM Documents__c WHERE Id IN :recordIds]) {
                if (String.isBlank(doc.portal_token_Id__c)) {
                    doc.portal_token_Id__c = UserInfo.getUserId() + String.valueOf((Integer)Math.floor(Math.random() * 1000));
                    docsToUpdate.add(doc);
                }
            }
            if (!docsToUpdate.isEmpty()) {
                update docsToUpdate;
            }
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}