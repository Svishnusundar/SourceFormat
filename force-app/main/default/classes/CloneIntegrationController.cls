/**
 * Handler class for cloneIntegrationQuickAction LWC.
 *
 * @author Prakhar Gupta
 * @version 1.0
    Test
 */
@SuppressWarnings('PMD')
public with sharing class CloneIntegrationController {
    private static List<FieldMapping__c> fieldMappingListtoInsert = new List<FieldMapping__c>();
    private static List<ObjectMapping__c> objectMappingListtoInsert = new List<ObjectMapping__c>();
    private static Map<String, String> objectMappingMap = new Map<String, String>();

    @AuraEnabled(cacheable=true)
    public static List<NamedCredential> getNamedCredentionals() {
        return [SELECT DeveloperName, Endpoint, Id, MasterLabel, PrincipalType FROM NamedCredential];
    }
    @AuraEnabled
    public static String cloneInegration(String jsonString, String recordId) {
        try {
            if (String.isEmpty(jsonString) || String.isBlank(jsonString)) {
                throw new ConnectException(System.Label.Invalid_record);
            }

            Map<String, Object> integrationMap = (Map<String, Object>) System.JSON.deserializeUntyped(jsonString);
            if (integrationMap != null && !integrationMap.isEmpty()) {
                Copado_Integration__c integration = populateIntegrationRecord(integrationMap);
                IIntegration integrationFactoryInstance = IntegrationFactory.returnInstance(integration.Provider__c);
                Object externalProject = integrationFactoryInstance.getProject(integration.Named_Credential__c, integration.External_Project_Key__c);
                String externalProjectId = integrationFactoryInstance.isValidConnection(externalProject);
                integration.External_Project_ID__c = externalProjectId;
                String copadoProjectId = '';
                copado__Project__c copadoProject = integrationFactoryInstance.createCopadoProject(externalProject, integration.Project__c);
                SObjectAccessDecision accessDecision = Security.stripInaccessible(
                    AccessType.UPSERTABLE,
                    new List<copado__Project__c>{ copadoProject }
                );
                if (copadoProject.id == null) {
                    upsert ((List<copado__Project__c>) accessDecision.getRecords()) External_Id__c;
                } else {
                    update accessDecision.getRecords();
                }

                List<copado__Project__c> copadoProjects = (List<copado__Project__c>) accessDecision.getRecords();
                copadoProjectId = copadoProjects[0].id;
                integration.Project__c = copadoProjectId;
                fflib_SecurityUtils.checkObjectIsInsertable(Copado_Integration__c.SObjectType);
                insert Integration;

                if (
                    integrationMap.containsKey(CommonIntegrationConstants.CloneIntegrationsettings) &&
                    Boolean.valueOf(integrationMap.get(CommonIntegrationConstants.CloneIntegrationsettings))
                ) {
                    handleMappings(recordId, integration);
                } else {
                    // Create default mapping if clone integration settings not checked
                    integrationFactoryInstance.createDefaultProjectMapping(integration.id);
                }

                return integration.id;
            } else {
                throw new ConnectException(System.Label.Internal_Server_Error);
            }
        } catch (ConnectException e) {
            throw new ConnectException(e.getMessage());
        }
    }

    private static Copado_Integration__c populateIntegrationRecord(Map<String, Object> integrationMap) {
        Copado_Integration__c integration = new Copado_Integration__c();
        if (integrationMap.containsKey(CommonIntegrationConstants.ConnectionName)) {
            integration.Name = String.valueOf(integrationMap.get(CommonIntegrationConstants.ConnectionName));
        }
        if (integrationMap.containsKey(CommonIntegrationConstants.namedCredential)) {
            integration.Named_Credential__c = String.valueOf(integrationMap.get(CommonIntegrationConstants.namedCredential));
        }
        if (integrationMap.containsKey(CommonIntegrationConstants.ProjectName)) {
            integration.Project__c = String.valueOf(integrationMap.get(CommonIntegrationConstants.ProjectName));
        }
        if (integrationMap.containsKey(CommonIntegrationConstants.externalProjectKey)) {
            integration.External_Project_Key__c = String.valueOf(integrationMap.get(CommonIntegrationConstants.externalProjectKey));
            if (!isConfigurationUniqueByProjectKey(integration.External_Project_Key__c)) {
                throw new ConnectException(System.Label.Unique_Copado_Integration_Validation_Error);
            }
        }
        if (integrationMap.containsKey(CommonIntegrationConstants.DESCRIPTION)) {
            integration.Description__c = String.valueOf(integrationMap.get(CommonIntegrationConstants.DESCRIPTION));
        }
        if (integrationMap.containsKey(CommonIntegrationConstants.Provider)) {
            integration.Provider__c = String.valueOf(integrationMap.get(CommonIntegrationConstants.Provider));
        }
        integration.Connection_Status__c = CommonIntegrationConstants.STATUS_CONNECTED;
        return integration;
    }

    private static void handleMappings(String recordId, Copado_Integration__c integration) {
        for (ObjectMapping__c objectMapping : [
            SELECT
                id,
                Salesforce_Object_Name__c,
                Salesforce_Object_Record_Type__c,
                External_Object_Name__c,
                External_Object_Record_Type_Label__c,
                External_Object_Record_Type__c,
                Status__c,
                Synced__c
            FROM ObjectMapping__c
            WHERE Copado_Integration__c = :recordId
            WITH SECURITY_ENFORCED
        ]) {
            ObjectMapping__c objectMappingtoInsert = new ObjectMapping__c();
            objectMappingtoInsert = objectMapping.clone(false);
            objectMappingtoInsert.Copado_Integration__c = integration.id;
            objectMappingMap.put(objectMapping.Salesforce_Object_Name__c + objectMapping.Salesforce_Object_Record_Type__c + objectMapping.External_Object_Record_Type__c, objectMapping.id);
            objectMappingListtoInsert.add(objectMappingtoInsert);
        }
        if (!objectMappingListtoInsert.isEmpty()) {
            ConnectUtilities.performSecureInsert(objectMappingListtoInsert, ObjectMapping__c.SObjectType);
            for (ObjectMapping__c objectMapping : objectMappingListtoInsert) {
                if (objectMappingMap.containsKey(objectMapping.Salesforce_Object_Name__c + objectMapping.Salesforce_Object_Record_Type__c + objectMapping.External_Object_Record_Type__c)) {
                    objectMappingMap.put(
                        objectMappingMap.remove(objectMapping.Salesforce_Object_Name__c + objectMapping.Salesforce_Object_Record_Type__c + objectMapping.External_Object_Record_Type__c),
                        objectMapping.id
                    );
                }
            }

            Map<String, List<Field_Value_Mapping__c>> valueMappingByFieldMapping = handleFieldMappingOperation(recordId, integration);
            ConnectUtilities.performSecureInsert(fieldMappingListtoInsert, FieldMapping__c.SObjectType);

            List<Field_Value_Mapping__c> valueMappings = handleValueMappingOperation(valueMappingByFieldMapping);
            ConnectUtilities.performSecureInsert(valueMappings, Field_Value_Mapping__c.SObjectType);
        }
    }

    private static List<Field_Value_Mapping__c> handleValueMappingOperation(Map<String, List<Field_Value_Mapping__c>> valueMappingByFieldMapping) {
        List<Field_Value_Mapping__c> valueMappings = new List<Field_Value_Mapping__c>();
        for (FieldMapping__c mapping : fieldMappingListtoInsert) {
            if (valueMappingByFieldMapping.containsKey(mapping.External_Field_Name__c + mapping.Salesforce_Object_Record_Type__c)) {
                for (
                    Field_Value_Mapping__c valueMapping : valueMappingByFieldMapping.get(
                        mapping.External_Field_Name__c + mapping.Salesforce_Object_Record_Type__c
                    )
                ) {
                    Field_Value_Mapping__c newValueMapping = valueMapping.clone(false);
                    newValueMapping.Field_Mapping__c = mapping.Id;
                    valueMappings.add(newValueMapping);
                }
            }
        }
        return valueMappings;
    }

    private static Map<String, List<Field_Value_Mapping__c>> handleFieldMappingOperation(String recordId, Copado_Integration__c integration) {
        Map<String, List<Field_Value_Mapping__c>> valueMappingByFieldMapping = new Map<String, List<Field_Value_Mapping__c>>();
        for (FieldMapping__c mapping : [
            SELECT
                Outbound__c,
                Salesforce_Object_Record_Type__c,
                External_Field_Name__c,
                Object_Mapping__c,
                External_Field_Type__c,
                Status__c,
                Copado_Is_Creatable__c,
                Copado_Is_Updatable__c,
                Salesforce_Field_Type__c,
                Inbound__c,
                Salesforce_Field_Name__c,
                (SELECT Id, Name, External_Field_Value__c, Field_Mapping__c, Salesforce_Field_Value__c FROM Field_Value_Mappings__r)
            FROM FieldMapping__c
            WHERE Copado_Integration__c = :recordId
            WITH SECURITY_ENFORCED
        ]) {
            FieldMapping__c newmapping = mapping.clone(false);
            newmapping.Copado_Integration__c = integration.id;
            newmapping.Object_Mapping__c = objectMappingMap.containsKey(mapping.Object_Mapping__c)
                ? objectMappingMap.get(mapping.Object_Mapping__c)
                : null;
            fieldMappingListtoInsert.add(newmapping);
            if (!mapping.Field_Value_Mappings__r.isEmpty()) {
                valueMappingByFieldMapping.put(
                    mapping.External_Field_Name__c + mapping.Salesforce_Object_Record_Type__c,
                    mapping.Field_Value_Mappings__r
                );
            }
        }
        return valueMappingByFieldMapping;
    }

    private static Boolean isConfigurationUniqueByProjectKey(String externalProjectKey) {
        List<Copado_Integration__c> records = [
            SELECT ID
            FROM Copado_Integration__c
            WHERE External_Project_Key__c = :externalProjectKey
            WITH SECURITY_ENFORCED
        ];
        return records.isEmpty();
    }
}