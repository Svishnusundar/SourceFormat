@SuppressWarnings('PMD')
public with sharing class ConnectSubscriberFactory {
    //Copado Constant naming conventian: https://gitlab.com/copado/app-dev/copado-best-practices/-/tree/master/Naming%20Conventions#parametersvariables
    private final String QUERY_TEMPLATE = 'SELECT {0} FROM {1} WHERE {2} WITH SECURITY_ENFORCED';
    private static Map<String, SubscriberOps> subscriberMap;
    public static Map<String, Schema.SObjectField> objectExternalFieldMapping;
    private static Map<String, Schema.SObjectField> objectFieldForDML;
    private final String PROJECT_OBJECT = 'copado__Project__c';
    private Map<String, String> appendixMapping = new Map<String, String>{
        'copado__Project__c' => copado__Project__c.Fields.External_Id__c.getDescribe().getName(),
        'copado__Sprint__c' => copado__Sprint__c.Fields.External_Id__c.getDescribe().getName(),
        'copado__Release__c' => copado__Release__c.Fields.External_Id__c.getDescribe().getName()
    };
    private List<String> appendixObjects = new List<String>(appendixMapping.keySet());
    private Map<String, Map<String, Object>> objectDetailsMap = new Map<String, Map<String, Object>>{
        'copado__Sprint__c' => new Map<String, Object>{
            'apiName' => copado__Sprint__c.SObjectType,
            'externalIdField' => copado__Sprint__c.Fields.External_Id__c
        },
        'copado__Release__c' => new Map<String, Object>{
            'apiName' => copado__Release__c.SObjectType,
            'externalIdField' => copado__Release__c.Fields.External_Id__c
        }
    };
    private Logger logs {
        get {
            if (null == logs) {
                logs = new Logger();
            }
            return logs;
        }
        set;
    }
    static {
        subscriberMap = new Map<String, SubscriberOps>();
        subscriberMap.put('copado_jira', new JiraSubscriberDTO());
        subscriberMap.put(ServiceNowIntegrationConstants.COPADO_SERVICENOW, new ServiceNowSubscriberDTO());
        objectExternalFieldMapping = new Map<String, Schema.SObjectField>();
        objectExternalFieldMapping.put(
            copado__Project__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__Project__c.Fields.External_Id__c
        );
        objectExternalFieldMapping.put(
            copado__Sprint__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__Sprint__c.Fields.External_ID__c
        );
        objectExternalFieldMapping.put(
            copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__User_Story__c.Fields.External_ID__c
        );
        objectExternalFieldMapping.put(
            copado__Release__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__Release__c.Fields.External_ID__c
        );
        objectExternalFieldMapping.put(
            copado__Epic__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__Epic__c.Fields.External_ID__c
        );
        objectExternalFieldMapping.put(
            copado__User_Story_Task__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__User_Story_Task__c.Fields.External_ID__c
        );

        objectFieldForDML = new Map<String, Schema.SObjectField>();
        objectFieldForDML.put(
            copado__Project__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__Project__c.Fields.External_Id__c
        );
        objectFieldForDML.put(copado__Sprint__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(), copado__Sprint__c.Fields.Id);
        objectFieldForDML.put(
            copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__User_Story__c.Fields.External_ID__c
        );
        objectFieldForDML.put(copado__Release__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(), copado__Release__c.Fields.Id);
        objectFieldForDML.put(
            copado__Epic__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__Epic__c.Fields.External_ID__c
        );
        objectFieldForDML.put(
            copado__User_Story_Task__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            copado__User_Story_Task__c.Fields.External_ID__c
        );
    }
    public static SubscriberOps getSubscriberOps(String subscriberKey) {
        if (subscriberMap.containsKey(subscriberKey)) {
            return subscriberMap.get(subscriberKey); //
        } else {
            return null;
        }
    }

    public void run(List<copado__Data_Change_Event__e> events) {
        copado.CopadoEventDecisionClassifier.toggleEventGeneration(true);
        for (copado__Data_Change_Event__e evt : events) {
            SubscriberOps ops = getSubscriberOps(evt.copado__Subscriber_Code__c);
            if (ops == null) {
                continue;
            }
            try {
                if (evt.copado__Subscriber_Code__c.equalsIgnoreCase(ServiceNowIntegrationConstants.COPADO_SERVICENOW)) {
                    ((ServiceNowSubscriberDTO) ops)
                        .setConfiguration((Copado_Integration__c) new ConfigurationAdaptor().adapt((Id) evt.copado__Record_ID__c));
                }
                ConnectAdaptor adapter;
                try {
                    adapter = ops
                        .getSubscriberAdaptors() // Map<String,ConnectServiceFactory>
                        .get(evt.copado__Base_Object__c) // ConnectAdaptorFactory
                        .adaptors
                        .get(evt.copado__Triggering_Action__c); // ConnectAdaptor
                } catch (Exception exc) {
                    Integration_Log__c log = logs.prepareCopadoToProvider(evt.copado__Record_ID__c, evt.copado__Base_Object__c);
                    log.Error_Message__c =
                        String.format(
                            Label.UNSUPPORTED_COPADO_EVENT,
                            new List<String>{ evt.copado__Triggering_Action__c, evt.copado__Base_Object__c }
                        ) +
                        ' ' +
                        exc.getMessage() +
                        exc.getStackTraceString();
                    log.Description__c = 'ConnectSubscriberFactory.run(CopadoToProvider)';
                    logs.addLog(log);
                    continue;
                }
                if (adapter != null) {
                    adapter.adapt((Id) evt.copado__Record_ID__c);
                    if (adapter.getConfiguration() != null) {
                        // Active Configuration exists
                        if (isRecursiveCall(evt.copado__Triggering_Action__c, adapter.getRecord(), evt.copado__Base_Object__c)) {
                            continue;
                        }
                        handleRecordUpdate(evt, ops, adapter);
                    }
                }
            } catch (Exception exc) {
                // Any unhandled exception is being saved to Global result
                Integration_Log__c log = logs.prepareCopadoToProvider(evt.copado__Record_ID__c, evt.copado__Base_Object__c);
                log.Error_Message__c = exc.getMessage() + exc.getStackTraceString();
                log.Description__c = 'ConnectSubscriberFactory.run(CopadoToProvider)';
                logs.addLog(log);
            }
            break; // realtime sync should have only one PE, This need to be tested
        }
        logs.saveLogs();
    }

    private void handleRecordUpdate(copado__Data_Change_Event__e evt, SubscriberOps ops, ConnectAdaptor adapter) {
        ICopadoEventHandler service = ops.getSubscriberServices().get(evt.copado__Base_Object__c).services.get(evt.copado__Triggering_Action__c);
        Sobject record;
        try {
            record = adaptResponse(evt, service, adapter);
        } catch (ApiException apiEx) {
            record = deactivateConnection(evt, apiEx, adapter);
            Integration_Log__c log = logs.prepareAPIException(evt.copado__Record_ID__c, apiEx);
            log.Copado_Integration__c = adapter.getConfiguration().Id;
            log.Sync_Direction__c = CommonIntegrationConstants.SYNC_COPADO_TO_PROVIDER;
            log.Description__c = 'ConnectSubscriberFactory.handleRecordUpdate';
            logs.addLog(log);
        }
        if (!evt.copado__Triggering_Action__c.equalsIgnoreCase(System.TriggerOperation.AFTER_DELETE.name())) {
            ConnectUtilities.performSecureUpdate(
                new List<SObject>{ record },
                ((SObject) Type.forName('Schema', evt.copado__Base_Object__c).newInstance()).getSObjectType(),
                false
            );
        }
    }

    private SObject deactivateConnection(copado__Data_Change_Event__e evt, ApiException apiEx, ConnectAdaptor adapter) {
        Sobject records2Upsert = ((Id) evt.copado__Record_ID__c).getSobjectType().newSobject(evt.copado__Record_ID__c);
        records2Upsert.put( // Update Connect_Log__c field for failure result
            CommonIntegrationConstants.CONNECT_LOG_FIELD_API_NAME,
            String.format(CommonIntegrationConstants.FAILED_CONNECT_LOG_TEMPLATE, new List<String>{ apiEx.getBody() })
        );
        if (
            ConnectUtilities.isConfigurationException(evt.copado__Subscriber_Code__c, adapter.getConfiguration(), apiEx, evt.copado__Base_Object__c)
        ) {
            ConnectUtilities.deactivateConnection(adapter.getConfiguration());
        }
        return records2Upsert;
    }

    private SObject adaptResponse(copado__Data_Change_Event__e evt, ICopadoEventHandler service, ConnectAdaptor adapter) {
        Sobject records2Upsert = ((Id) evt.copado__Record_ID__c).getSobjectType().newSobject(evt.copado__Record_ID__c);
        Object inputBean = adapter.adapt((Id) evt.copado__Record_ID__c);
        String namedCredential = adapter.getConfiguration().Named_Credential__c;
        Object response = service.execute(namedCredential, inputBean);
        if (
            evt.copado__Triggering_Action__c.equalsIgnoreCase(System.TriggerOperation.AFTER_INSERT.name()) ||
            evt.copado__Triggering_Action__c.equalsIgnoreCase(System.TriggerOperation.AFTER_UNDELETE.name())
        ) {
            records2Upsert = adapter.adapt(response); // convert Model into SObject
        }
        records2Upsert.put(CommonIntegrationConstants.LAST_SYNCED_DATE_FIELD, System.now());
        records2Upsert.put(CommonIntegrationConstants.CONNECT_LOG_FIELD_API_NAME, CommonIntegrationConstants.SUCCESS);
        return records2Upsert;
    }

    public void run(List<copado__Event__e> events) {
        //trigger.new as paramll
        copado.CopadoEventDecisionClassifier.toggleEventGeneration(true);
        for (copado__Event__e evt : events) {
            SubscriberOps ops = getSubscriberOps(evt.copado__Publisher_Code__c);
            if (ops == null) {
                continue;
            }
            try {
                System.debug('evt.copado__Payload__c value: ' + evt.copado__Payload__c);
                WebhookPayload payLoad = (WebhookPayload) JSON.deserialize(evt.copado__Payload__c, ops.getWebHookPayloadType());
                System.debug('payLoad value: ' + payLoad);
                String objectName = payLoad.getObjectName();
                if (evt.copado__Publisher_Code__c.equalsIgnoreCase(ServiceNowIntegrationConstants.COPADO_SERVICENOW)) {
                    ((ServiceNowSubscriberDTO) ops)
                        .setConfiguration((Copado_Integration__c) new ConfigurationAdaptor(objectName).adapt(payLoad.getProjectID()));
                }
                ConnectAdaptor adapter;
                try {
                    adapter = ops
                        .getSubscriberAdaptors() // Map<String,ConnectServiceFactory>
                        .get(objectName)
                        .adaptors
                        .get(CommonIntegrationConstants.GET); // ConnectAdaptor
                } catch (Exception exc) {
                    Integration_Log__c log = logs.prepareProviderToCopado(evt.copado__Payload__c);
                    log.Error_Message__c = Label.UNSUPPORTED_PROVIDER_EVENT + ' ' + exc.getMessage() + exc.getStackTraceString();
                    log.Description__c = 'ConnectSubscriberFactory.run(ProviderToCopado)';
                    logs.addLog(log);
                    continue;
                }

                Object inputBean = adapter.adapt(evt.copado__Payload__c);
                if (adapter.getConfiguration() != null) {
                    //Active Configuration exists
                    try {
                        executeActiveConfiguration(evt, payLoad, adapter, inputBean);
                    } catch (ApiException apiEx) {
                        logs.logAPIException(adapter.getConfiguration().Id, apiEx);
                    }
                }
            } catch (Exception exc) {
                // any unhandled Exception
                Integration_Log__c log = logs.prepareProviderToCopado(evt.copado__Payload__c);
                log.Error_Message__c = exc.getMessage() + exc.getStackTraceString();
                log.Description__c = 'ConnectSubscriberFactory.run(ProviderToCopado)';
                logs.addLog(log);
            }
            break; // realtime sync should have only one PE. This need to be tested
        }
        logs.saveLogs();
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    //inputBean has to be called before getConfiguration() hence it has to be added as a fourth parameter
    private void executeActiveConfiguration(copado__Event__e evt, WebhookPayload payload, ConnectAdaptor adapter, Object inputBean) {
        String objectName = payLoad.getObjectName();
        SubscriberOps ops = getSubscriberOps(evt.copado__Publisher_Code__c);
        ICopadoEventHandler service = ops.getSubscriberServices().get(objectName).services.get(CommonIntegrationConstants.GET);
        String namedCredential = adapter.getConfiguration().Named_Credential__c;
        // SF can have standard JIRA external Id or in case of one project to multiple then externalId-Appendix version
        List<String> sfExternalIds = getSfExternalIds(objectName, payload, adapter);
        Map<Id, SObject> oldRecords = ConnectUtilities.querySobjectsByExternalID(payLoad.getExternalID(), objectName);
        if (
            payLoad.getEvent().equalsIgnoreCase('Delete') &&
            (oldRecords.isempty() || isDataChangeEventAllowOperation(oldRecords, oldRecords, payLoad, evt.copado__Publisher_Code__c, objectName))
        ) {
            deleteCopadoRecord(payLoad, objectName);
        } else {
            Object responseModel = service.execute(namedCredential, inputBean);
            List<SObject> copadoRecords = new List<SObject>();
            if (!adapter.getConfigurations().isEmpty()) {
                copadoRecords = adapter.adaptList(responseModel);
            } else {
                Sobject copadoObject = adapter.adapt(responseModel);
                if (PROJECT_OBJECT == objectName) {
                    if (!sfExternalIds.isEmpty()) {
                        for (String id : sfExternalIds) {
                            Sobject clonedObject = copadoObject.clone(false, true, false, false);
                            clonedObject.put(copado__Project__c.Fields.External_Id__c.getDescribe().getName(), id);
                            copadoRecords.add(clonedObject);
                        }
                    }
                }
                if (!oldRecords.isEmpty()) {
                    // Doesn't suppot Jira Insert data change condition
                    copadoObject.put('Id', oldRecords.values().get(0).get('Id'));
                }
                if (
                    !isDataChangeEventAllowOperation(
                        new Map<Id, Sobject>{ (Id) copadoObject.get('id') => copadoObject },
                        oldRecords,
                        payLoad,
                        evt.copado__Publisher_Code__c,
                        objectName
                    )
                ) {
                    return; // Data change event is configured to not process records.
                }
                if (copadoRecords.isEmpty()) {
                    copadoRecords.add(copadoObject);
                }
            }

            handleUpsert(copadoRecords, payLoad, adapter);
        }
    }

    private List<String> getSfExternalIds(String objectName, WebhookPayload payload, ConnectAdaptor adapter) {
        List<String> sfExternalIds = new List<String>();
        if (appendixObjects.contains(objectName)) {
            String sfExternalId = (PROJECT_OBJECT == objectName) ? adapter.getConfiguration().External_Project_ID__c : payload.getExternalID();
            sfExternalIds = getAllExternalIdWithAppendix(objectName, sfExternalId);
            if (!sfExternalIds.isEmpty() && PROJECT_OBJECT != objectName) {
                objectFieldForDML.put(
                    ((Schema.SObjectType) objectDetailsMap.get(objectName).get('apiName')).getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
                    ((Schema.SObjectField) objectDetailsMap.get(objectName).get('externalIdField'))
                );
            }
        }
        return sfExternalIds.isEmpty() ? new List<String>() : sfExternalIds;
    }

    private List<String> getAllExternalIdWithAppendix(String objectName, String externalId) {
        List<SObject> results = new List<SObject>();
        List<String> externalIds = new List<String>();

        if (PROJECT_OBJECT == objectName) {
            externalId = externalId.split('-')[0];
        }

        String FIELDS = 'Id, ' + appendixMapping.get(objectName);
        String CONDITIONS = 'WHERE ' + appendixMapping.get(objectName) + ' LIKE \'' + String.escapeSingleQuotes(externalId) + '-%\'';

        // NOTE: This query construction triggers a security flag for potential SOQL injection.
        // However, this is a false positive because:
        // 1. The variable 'externalId' is sanitized using String.escapeSingleQuotes() to prevent SOQL injection.
        // 2. The dynamic part of the query (externalId) is controlled and does not expose direct injection points.
        // This ensures that the query remains secure against SOQL injection attacks, and the flag can be safely dismissed.
        String query = 'SELECT ' + FIELDS + ' FROM ' + objectName + ' ' + CONDITIONS + ' WITH SECURITY_ENFORCED';
        results = Database.query(query);

        for (SObject record : results) {
            externalIds.add((String) record.get(appendixMapping.get(objectName)));
        }
        return externalIds;
    }

    //line 218 has to be in a loop since the object is dynamic and might be difference and specific Sobject type is needed for the upsert operation
    private void handleUpsert(List<SObject> copadoObject, WebhookPayload payLoad, ConnectAdaptor adapter) {
        String objectName = payLoad.getObjectName();
        for (SObject obj : copadoObject) {
            obj.put(CommonIntegrationConstants.LAST_SYNCED_DATE_FIELD, System.now());
        }
        List<Database.UpsertResult> results = ConnectUtilities.performSecureUpsert(
            copadoObject,
            ((SObject) Type.forName('Schema', objectName).newInstance()).getSObjectType(),
            objectFieldForDML.get(objectName)
        );

        for (Database.UpsertResult result : results) {
            if (!result.isSuccess()) {
                Integration_Log__c log = logs.createDefaultResult();
                log.Error_Message__c = ConnectUtilities.getAllFailedCause(new List<Database.UpsertResult>{ result });
                log.Result_Data__c = +JSON.serialize(copadoObject);
                log.Object_Name__c = objectName;
                log.External_ID__c = payLoad.getExternalID();
                log.Sync_Direction__c = CommonIntegrationConstants.SYNC_PROVIDER_TO_COPADO;
                log.Description__c = 'ConnectSubscriberFactory.handleUpsert';
                ConnectUtilities.updateFailedMapping(new List<Database.UpsertResult>{ result }, copadoObject, adapter.getConfiguration(), objectName);
                logs.addLog(log);
            }
        }
    }
    /**
     * Delete record from salesforce if records exisings otherwise ignore.
     */
    private void deleteCopadoRecord(WebhookPayload payLoad, String objectName) {
        List<sObject> copadoObjects = Database.query(
            String.format(
                QUERY_TEMPLATE,
                new List<String>{ 'Id', objectName, objectExternalFieldMapping.get(objectName) + ' LIKE \'' + payLoad.getExternalID() + '%\'' }
            )
        );
        if (!copadoObjects.isEmpty()) {
            ConnectUtilities.performSecureDelete(copadoObjects, ((SObject) Type.forName('Schema', objectName).newInstance()).getSObjectType());
        }
    }
    /*
     * If Insert trigger action has external Id that mean it is due to DML of Connect2Copado
     */
    private boolean isRecursiveCall(String triggerAction, Sobject record, String objectAPIName) {
        if (
            triggerAction.equalsIgnoreCase(System.TriggerOperation.AFTER_INSERT.name()) &&
            record.get(objectExternalFieldMapping.get(objectAPIName)) != null
        ) {
            return true;
        }
        return false;
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    //long list of parameters are must in this method
    private static boolean isDataChangeEventAllowOperation(
        Map<Id, SObject> newRecords,
        Map<Id, SObject> oldRecords,
        WebhookPayload payLoad,
        String publisherCode,
        String objectApiName
    ) {
        List<Object> records = copado.CopadoEventDecisionClassifier.getEventDecisions(
            newRecords,
            oldRecords,
            'AFTER_' + payLoad.getEvent(),
            publisherCode,
            objectApiName
        );
        return records.isEmpty() ? false : true;
    }
}