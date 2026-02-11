@SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
public abstract with sharing class AbstractConnectAdaptor implements ConnectAdaptor {
    private static final String INACTIVE = 'Inactive';
    private static final String USER_STORY_OBJECT = 'copado__User_Story__c';
    private static final String USER_STORY_TASK_OBJECT = 'copado__User_Story_Task__c';
    private static final String RELEASE_OBJECT = 'copado__Release__c';
    private static final String SPRINT_OBJECT = 'copado__Sprint__c';

    private static final String QUERY_TEMPLATE = 'SELECT {0} FROM {1} WHERE Id=:recordId WITH SECURITY_ENFORCED ALL ROWS';

    private Id recordId;
    protected SObject record;
    protected List<SObject> records;

    protected Set<String> objectFields;
    protected String objectType;
    protected Copado_Integration__c configuration;
    protected List<Copado_Integration__c> configurationList = new List<Copado_Integration__c>();
    protected String jiraIssueKey = null;
    protected List<Copado_Integration__c> validConfigurationList = new List<Copado_Integration__c>();

    protected Map<String, FieldMapping__c> copadoFieldMapping;
    protected Map<String, FieldMapping__c> almFieldMapping;
    Map<String, String> projectLookup = new Map<String, String>();
    protected String sfRecordTypeName = null;
    protected String externalRTName = null;

    public AbstractConnectAdaptor() {
        // SObject field which connect to Project
        projectLookup.put(copado__Project__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(), 'copado__Project__c');
        projectLookup.put(copado__Sprint__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(), 'copado__Project__c');
        projectLookup.put(copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(), 'copado__Project__c');
        projectLookup.put(copado__Release__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(), 'copado__Project__c');
        projectLookup.put(
            copado__Epic__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            'copado__Release__r.copado__Project__c'
        );
        projectLookup.put(
            copado__User_Story_Task__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            'copado__User_Story__r.copado__Project__c'
        );
    }

    // Only for Jira to Copado
    public void init(String projectKey, String objectType) {
        this.objectType = objectType;
        fetchConfiguration(projectKey);
        if (configuration != null) {
            fetchMapping();
        }
    }

    // Only for Copado to Jira
    public void init(Id recordId) {
        this.recordId = recordId;
        this.objectType = recordId.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        ID relatedProjectID = findProjectID();
        if (record != null) {
            sfRecordTypeName = findRecordTypeName();
        }
        fetchConfiguration(relatedProjectID);
        if (configuration != null) {
            fetchMapping();
            fetchRecord();
            if (copadoFieldMapping.isEmpty()) {
                System.debug('DEBUG[AbstractConnectAdaptor] init(Id): copadoFieldMapping is empty, clearing configuration');
                configuration = null;
            }
        } else {
            System.debug('DEBUG[AbstractConnectAdaptor] init(Id): configuration is null after fetchConfiguration');
        }
    }

    // Adaptor for organization-level resources like Teams
    public void initByOrg(String organizationId, String externalProjectId, String objectType) {
        this.objectType = objectType;
        if (null == configuration) {
            configuration = fetchConfigurationByOrg(organizationId, externalProjectId);
        }
        if (configuration != null) {
            fetchMapping();
        }
    }

    public void updateMappingForConfiguration(Copado_Integration__c ciRecord) {
        configuration = ciRecord;
        System.debug('DEBUG[AbstractConnectAdaptor] updateMappingForConfiguration: Configuration set to: ' + (ciRecord != null ? ciRecord.Id : 'null'));
        fetchMapping();
    }

    // Only for Copado to Jira
    private void fetchRecord() {
        if (!objectFields.isEmpty()) {
            setRecord(
                Database.query(String.format(QUERY_TEMPLATE, new List<String>{ String.join(new List<String>(objectFields), ','), objectType }))
            );
        }
    }

    // Only for Copado to Jira
    private void setRecord(SObject record) {
        this.record = record;
    }

    private void fetchConfiguration(String projectKey) {
        if (null == configuration) {
            Copado_Integration__c[] configurations = [
                SELECT
                    Name,
                    ID,
                    External_Project_ID__c,
                    Project__c,
                    Organization__c,
                    External_Project_Key__c,
                    Named_Credential__c,
                    JQL_Extended_Filter__c,
                    Appendix__c,
                    Server_Info__c,
                    (
                        SELECT Id
                        FROM Field_Mappings__r
                        WHERE Salesforce_Object__c = :objectType
                    ),
                    (
                        SELECT Id
                        FROM Object_mappings__r
                        WHERE Salesforce_Object_Name__c = :objectType AND External_Object_Record_Type__c = :externalRTName
                    )
                FROM Copado_Integration__c
                WHERE External_Project_Key__c = :projectKey AND Integration_Status__c != :INACTIVE
                WITH SECURITY_ENFORCED
            ];

            System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(String): Found ' + configurations.size() + ' configurations for projectKey=' + projectKey + ', objectType=' + objectType);
            System.debug('field mappings size: ' + (configurations.size() > 0 ? configurations[0]?.Field_Mappings__r.size() : 0));
            System.debug('object mappings size: ' + (configurations.size() > 0 ? configurations[0]?.Object_mappings__r.size() : 0));

            if (configurations.size() == 1 && configurations[0]?.Field_Mappings__r.size() > 0 && configurations[0]?.Object_mappings__r.size() > 0) {
                configuration = configurations.get(0);
                System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(String): Single valid configuration set: ' + configuration.Id);
            } else if (configurations.size() > 1) {
                for (Copado_Integration__c ciRecord : configurations) {
                    if (ciRecord?.Field_Mappings__r.size() > 0 && ciRecord?.Object_mappings__r.size() > 0) {
                        configuration = ciRecord;
                        configurationList.add(configuration);
                        System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(String): Added valid configuration: ' + configuration.Id);
                    }
                }
            } else if (objectType == USER_STORY_TASK_OBJECT) {
                this.objectType = USER_STORY_OBJECT;
                System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(String): Switching to USER_STORY_OBJECT');
                fetchConfiguration(projectKey);
            }

            if (objectType == USER_STORY_OBJECT) {
                fetchUserStoryConfiguration(projectKey);
            }

            if (configurationList.size() > 1 && (objectType == RELEASE_OBJECT || objectType == SPRINT_OBJECT)) {
                validConfigurationList.addAll(configurationList);
                System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(String): Multiple valid configurations for Release/Sprint');
            }
        }
    }

    private void fetchUserStoryConfiguration(String projectKey) {
        if (configurationList.size() > 1) {
            configuration = null;
            Integer validJQLConfig = 0;
            for (Copado_Integration__c ciRecord : configurationList) {
                JiraGetIssuesModel jiraGetIssuesModel = verifyIssueWithJQL(jiraIssueKey, projectKey, ciRecord);
                if (jiraGetIssuesModel.issues.size() == 1) {
                    configuration = ciRecord;
                    validJQLConfig++;
                    System.debug('DEBUG[AbstractConnectAdaptor] fetchUserStoryConfiguration: Valid JQL config found: ' + ciRecord.Id);
                }
                if (validJQLConfig > 1) {
                    System.debug('DEBUG[AbstractConnectAdaptor] fetchUserStoryConfiguration: More than one valid JQL config!');
                    throw new ConnectException(String.format(Label.JQL_DUPLICATE, new List<String>{ configuration.Name, ciRecord.Name }));
                }
            }
        } else if (null != configuration && String.isNotBlank(configuration.JQL_Extended_Filter__c)) {
            JiraGetIssuesModel jiraGetIssuesModel = verifyIssueWithJQL(jiraIssueKey, projectKey, configuration);
            if (jiraGetIssuesModel.issues.size() != 1) {
                System.debug('DEBUG[AbstractConnectAdaptor] fetchUserStoryConfiguration: JQL not satisfied, clearing configuration');
                configuration = null; //JQL not statisfied
            }
        }
    }

    private JiraGetIssuesModel verifyIssueWithJQL(String jiraIssueKey, String projectKey, Copado_Integration__c ciRecord) {
        JiraIssuesGetInputBean issueInputBean = new JiraIssuesGetInputBean();
        JiraGetServerInfoModel serverInfo;
        if(null != ciRecord.Server_Info__c){
            serverInfo = (JiraGetServerInfoModel) JSON.deserialize(ciRecord.Server_Info__c, JiraGetServerInfoModel.class);
        }
        String jqlTemplate = 'key={0} AND Project={1} AND ({2})';
        issueInputBean.deploymentType = serverInfo?.deploymentType;
        issueInputBean.jQuery = String.format(jqlTemplate, new List<String>{ jiraIssueKey, projectKey, ciRecord.JQL_Extended_Filter__c });
        JiraGetIssuesModel jiraGetIssuesModel = (JiraGetIssuesModel) new JiraGetIssuesService().execute(ciRecord.Named_Credential__c, issueInputBean);
        return jiraGetIssuesModel;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation') //false positive
    private void fetchConfiguration(ID relatedProjectID) {
        Copado_Integration__c[] configurations = [
            SELECT
                Name,
                ID,
                External_Project_ID__c,
                Organization__c,
                External_Project_Key__c,
                Named_Credential__c,
                Project__c,
                (
                    SELECT Id
                    FROM Field_Mappings__r
                    WHERE Salesforce_Object__c = :objectType
                )
            FROM Copado_Integration__c
            WHERE Project__c = :relatedProjectID AND Integration_Status__c != :INACTIVE
            WITH SECURITY_ENFORCED
        ];
        System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(Id): Found ' + configurations.size() + ' configurations for projectId=' + relatedProjectID + ', objectType=' + objectType);
        if (configurations.size() > 0 && configurations[0]?.Field_Mappings__r.size() > 0) {
            if (objectType == USER_STORY_OBJECT && sfRecordTypeName != null) {
                fflib_SecurityUtils.checkObjectIsReadable(ObjectMapping__c.SObjectType);
                List<ObjectMapping__c> objMap = [
                    SELECT Id
                    FROM ObjectMapping__c
                    WHERE
                        Copado_Integration__r.Project__c = :relatedProjectID
                        AND Salesforce_Object_Name__c = :objectType
                        AND Salesforce_Object_Record_Type__c = :sfRecordTypeName
                ];
                System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(Id): Found ' + objMap.size() + ' object mappings for recordType=' + sfRecordTypeName);
                configuration = objMap.size() > 0 ? configurations.get(0) : configuration;
                if (configuration != null) System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(Id): Configuration set: ' + configuration.Id);
            } else {
                configuration = configurations.get(0);
                System.debug('DEBUG[AbstractConnectAdaptor] fetchConfiguration(Id): Configuration set: ' + configuration.Id);
            }
        }
    }

    private Copado_Integration__c fetchConfigurationByOrg(String organizationId, String externalProjectId) {
        Copado_Integration__c[] configurations = [
            SELECT
                Name,
                ID,
                External_Project_ID__c,
                Project__c,
                Organization__c,
                External_Project_Key__c,
                Named_Credential__c,
                JQL_Extended_Filter__c,
                Appendix__c,
                (
                    SELECT Id
                    FROM Field_Mappings__r
                    WHERE Salesforce_Object__c = :objectType
                ),
                (
                    SELECT Id
                    FROM Object_mappings__r
                    WHERE Salesforce_Object_Name__c = :objectType
                )
            FROM Copado_Integration__c 
            WHERE Organization__c = :organizationId AND External_Project_ID__c = :externalProjectId
            AND Integration_Status__c != :INACTIVE
            WITH SECURITY_ENFORCED
        ];

        System.debug('DEBUG[AbstractConnectAdaptor] fetchConfigurationByOrg: Found ' + configurations.size() + ' configurations for orgId=' + organizationId + ', externalProjectId=' + externalProjectId);
        if (!configurations.isEmpty() && configurations[0]?.Field_Mappings__r.size() > 0 && configurations[0]?.Object_mappings__r.size() > 0) {
            System.debug('DEBUG[AbstractConnectAdaptor] fetchConfigurationByOrg: Returning configuration: ' + configurations[0].Id);
            return configurations[0];
        }
        System.debug('DEBUG[AbstractConnectAdaptor] fetchConfigurationByOrg: No valid configuration found');
        return null;
    }

    private void fetchMapping() {
        copadoFieldMapping = new Map<String, FieldMapping__c>();
        almFieldMapping = new Map<String, FieldMapping__c>();
        objectFields = new Set<String>();
        // fetch field mapping for given sobject
        for (FieldMapping__c fm : [
            SELECT
                ID,
                Salesforce_Object__c,
                Salesforce_Field_Name__c,
                Salesforce_Field_Type__c,
                External_Object__c,
                External_Field_Name__c,
                External_Field_Type__c,
                Outbound__c,
                Inbound__c,
                Salesforce_Object_Record_Type__c,
                External_Object_Record_Type__c,
                (SELECT id, External_Field_Value__c, Salesforce_Field_Value__c FROM Field_Value_Mappings__r)
            FROM FieldMapping__c
            WHERE
                Copado_Integration__c = :configuration.id
                AND Salesforce_Object__c = :objectType
                AND (Salesforce_Object_Record_Type__c = :sfRecordTypeName
                OR External_Object_Record_Type__c = :externalRTName)
            WITH SECURITY_ENFORCED
        ]) {
            objectFields.add(fm.Salesforce_Field_Name__c.trim().toLowerCase());
            if (String.isBlank(fm.External_Field_Type__c)) {
                // Field external type is blank then treat them as text field.
                fm.External_Field_Type__c = CommonIntegrationConstants.TEXT;
            }
            if (fm.Salesforce_Field_Type__c == CommonIntegrationConstants.REFERENCE_STRING) {
                addReferenceExternalIdField(fm);
            }
            objectFields.add(CommonIntegrationConstants.COPADO_EXTERNAL_ID_FIELD.toLowerCase());
            if (fm.Outbound__c) {
                copadoFieldMapping.put(fm.Salesforce_Field_Name__c, fm);
            }
            if (fm.Inbound__c) {
                almFieldMapping.put(fm.External_Field_Name__c, fm);
            }
        }
    }

    // Add External Id for Reference Fields
    @SuppressWarnings(
        'PMD.EagerlyLoadedDescribeSObjectResult, PMD.NcssMethodCount, PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.AvoidDeeplyNestedIfStmts'
    )
    //line 193, 201, 209 are false positive PMD error since FieldDescribeOptions enum does not have deferred option unlike SObjectDescribeOptions
    private void addReferenceExternalIdField(FieldMapping__c fm) {
        SObjectType sObjType = Schema.getGlobalDescribe().get(objectType);
        Schema.DescribeFieldResult fieldResult = fflib_SObjectDescribe.getDescribe(objectType).getField(fm.Salesforce_Field_Name__c)?.getDescribe();
        if (fieldResult != null) {
            for (Schema.SObjectType reference : fieldResult.getReferenceTo()) {
                // In case of Self LookUp Parent Id - User Story(SubTask) reference
                if (
                    sObjType.getDescribe(SObjectDescribeOptions.DEFERRED) == reference.getDescribe(SObjectDescribeOptions.DEFERRED) &&
                    ConnectSubscriberFactory.objectExternalFieldMapping.get(objectType) != null
                ) {
                    objectFields.add(
                        fieldResult.relationshipname + '.' + ConnectSubscriberFactory.objectExternalFieldMapping.get(objectType).getDescribe().Name
                    );
                } else {
                    // In case of Project, Sprint, Release and Epic Reference
                    if (ConnectSubscriberFactory.objectExternalFieldMapping.get(fm.Salesforce_Field_Name__c) != null) {
                        objectFields.add(
                            fieldResult.relationshipname +
                                '.' +
                                ConnectSubscriberFactory.objectExternalFieldMapping.get(fm.Salesforce_Field_Name__c).getDescribe().Name
                        );
                    }
                    // Other reference fields where external id exists
                    else if (
                        reference.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .fields.getMap()
                            .get(CommonIntegrationConstants.ns + CommonIntegrationConstants.COPADO_EXTERNAL_ID_FIELD) != null
                    ) {
                        objectFields.add(fieldResult.relationshipname + '.' + CommonIntegrationConstants.COPADO_EXTERNAL_ID_FIELD);
                    } else if (fm.External_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.USER_TXT)) {
                        objectFields.add(fieldResult.relationshipname + '.' + User.Fields.Email);
                    }
                }
            }
        }
    }

    private ID findProjectID() {
        if (objectType == copado__Project__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()) {
            return recordId;
        } else {
            // Query record if Object is not Project
            if (objectType == copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()) {
                setRecord(
                    Database.query(String.format(QUERY_TEMPLATE, new List<String>{ projectLookup.get(objectType) + ', RecordTypeId', objectType }))
                );
            } else {
                setRecord(Database.query(String.format(QUERY_TEMPLATE, new List<String>{ projectLookup.get(objectType), objectType })));
            }
            if (objectType == copado__Epic__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()) {
                if (record.get('copado__Release__c') != null) {
                    return (ID) record.getSObject('copado__Release__r').get('copado__Project__c');
                } else {
                    return null;
                }
            }
            if (objectType == copado__User_Story_Task__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()) {
                if (record.get('copado__User_Story__c') != null) {
                    return (ID) record.getSObject('copado__User_Story__r').get('copado__Project__c');
                } else {
                    return null;
                }
            }
            return (ID) record.get(projectLookup.get(objectType));
        }
    }

    private String findRecordTypeName() {
        if (
            objectType == copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName() &&
            record.get(CommonIntegrationConstants.RECORD_TYPE_ID) != null
        ) {
            return ConnectUtilities.getRecordTypeNameById(objectType, (ID) record.get(CommonIntegrationConstants.RECORD_TYPE_ID));
        } else if (objectType == copado__Epic__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()) {
            return 'Master';
        } else if (objectType == copado__User_Story_Task__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()) {
            return 'Master';
        }
        return null;
    }

    public Copado_Integration__c getConfiguration() {
        return configuration;
    }

    public virtual List<Copado_Integration__c> getConfigurations() {
        return validConfigurationList;
    }
    public SObject getRecord() {
        return record;
    }
    abstract object adapt(Id recordId);
    abstract object adapt(String almRecordId);
    abstract Sobject adapt(Object response);

    public virtual List<SObject> adaptList(Object response) {
        //Implement this methode in adaptor classes for Mutiple configuration updates
        System.debug('delete me');
        return null;
    }
    
    
}