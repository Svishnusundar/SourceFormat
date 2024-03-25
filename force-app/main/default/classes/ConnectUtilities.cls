@SuppressWarnings('PMD.ExcessivePublicCount, PMD.CognitiveComplexity, PMD.CyclomaticComplexity, PMD.ApexCRUDViolation, PMD.StdCyclomaticComplexity')
public with sharing class ConnectUtilities {
    //constants
    private static final List<String> MONTHS = new List<String>{
        '',
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC'
    };
    private static String applySalesforceDateFormatString(Object param) {
        String dateString = String.valueOf(param);
        // convert DD/MMM/YYYY to format YYYY/MM/DD
        if (Pattern.matches('^\\d{1,2}/[a-zA-Z]{3}/\\d{2}$', dateString)) {
            dateString = applyMonthNumberFormateString(dateString);
        }

        return dateString.replace('Z', '+0000');
    }
    private static String applySalesforceDateTimeFormatString(Object param) {
        String dateString = String.valueOf(param);
        // convert DD/MMM/YYYY to format YYYY-MM-DD hh:mm:ss
        if (Pattern.matches('\\d{4}-\\d{1,2}-\\d{1,2}', dateString)) {
            Datetime dt = date.valueOf(dateString);
            dateString = String.valueOf(dt);
        }
        // convert DD/MMM/YYYY to format YYYY/MM/DD hh:mm:ss
        if (Pattern.matches('^\\d{1,2}/[a-zA-Z]{3}/\\d{2}$', dateString)) {
            dateString = applyMonthNumberFormateString(dateString);
            Datetime dt = date.valueOf(dateString);
            dateString = String.valueOf(dt);
        }
        return dateString.replace('T', ' ');
    }

    // convert DD/MMM/YYYY to Salesforce Format YYYY/MM/DD
    private static String applyMonthNumberFormateString(String param) {
        String monthName = param.replaceAll('[^a-zA-Z]+', '');
        param = param.replace(monthName, string.valueOf(MONTHS.indexOf(monthName.toUpperCase()))); //From DD/MMM/YYYY to DD/MM/YY
        param = String.valueOf(date.parse(param)); //From DD/MM/YY to YYYY/MM/YY
        return param;
    }

    //casts value based on the current sObject field
    public static Object castToCopadoField(Object param, String fname, String fldType) {
        if (param == null) {
            return param;
        }
        if (fldType == 'textarea' || fldType == 'picklist' || fldType == 'reference') {
            FldType = 'string';
        }
        switch on fldType.toLowerCase() {
            when 'boolean' {
                return Boolean.valueOf(param);
            }
            when 'string' {
                return String.valueOf(param);
            }
            when 'blob' {
                return (Blob) param;
            }
            when 'date' {
                return Date.valueOf(applySalesforceDateFormatString(param));
            }
            when 'datetime' {
                return Datetime.valueOf(applySalesforceDateTimeFormatString(param));
            }
            when 'time' {
                return (Time) param;
            }
            when 'integer' {
                return Integer.valueOf(param);
            }
            when 'long' {
                return (Long) param;
            }
            when 'decimal' {
                return (Decimal) param;
            }
            when 'double' {
                return Double.valueOf(param);
            }
            when else {
                return String.valueOf(param);
            }
        }
    }

    public static String castToServiceNowValue(Object fieldValue, String fieldType) {
        if (fieldType.equalsIgnoreCase('DATETIME')) {
            fieldValue = (String.valueOf(fieldValue)).substringBefore('.').replace('T', ' ');
        } else if (fieldType.equalsIgnoreCase('TIME')) {
            fieldValue = (String.valueOf(fieldValue)).substringBefore('.');
        }
        return String.valueOf(fieldValue);
    }

    // Apply Jira Date format
    private static String applyJiraDateFormatString(Object param) {
        return String.valueOf(param).replace('+0000', 'Z');
    }

    // Apply Jira DateTime format
    private static String applyJiraDateTimeFormatString(Object param) {
        return String.valueOf(param).replace(' ', 'T');
    }

    // Applu Jira Date( DD/MMM/YYYY) format
    public static String applyJiraDateMonthFormatString(String param) {
        date mydate = date.valueof(param);
        String dateString = mydate.day() + '/' + MONTHS.get(mydate.month()) + '/' + string.valueof(mydate.year()).right(2);
        return dateString;
    }

    // Method retuns copado recordtypeid
    public static Id getRecordTypeIdbyName(String objectName, String strRecordTypeName) {
        return Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get(strRecordTypeName)
            .getRecordTypeId();
    }

    // Method retuns copado recordtype.developerName
    public static String getRecordTypeNameById(String objectName, Id strRecordTypeId) {
        return Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosById()
            .get(strRecordTypeId)
            .getDeveloperName();
    }

    // Convert Record into JiraIssueInputBean
    public static JiraIssueInputBean createJiraIssueInputBean(Map<String, FieldMapping__c> copadoFieldMapping, sObject record, String projectKey) {
        JiraIssueInputBean inputBean = new JiraIssueInputBean();
        Map<String, Object> fields = new Map<String, Object>();
        String externalRecordType;

        for (String salesforceFieldName : copadoFieldMapping.keySet()) {
            FieldMapping__c fieldMapping = copadoFieldMapping.get(salesforceFieldName);
            if (
                fieldMapping.External_Field_Name__c.equalsIgnoreCase(CommonIntegrationConstants.ID) ||
                fieldMapping.External_Field_Name__c.equalsIgnoreCase(CommonIntegrationConstants.ISSUE_KEY)
            ) {
                continue; // ID or issueKey should be mapped from Salesforce to Jira only but if User mapped then we ignore.
            }
            externalRecordType = fieldMapping.External_Object_Record_Type__c;
            Object fieldValue = record.get(salesforceFieldName);

            if (fieldValue != null) {
                fieldValue = getFieldValue(fieldMapping, record, fieldValue);
            } // If field is blank then it must not be part of JIRA_BLANK_NOT_ALLOWED. JIRA_BLANK_NOT_ALLOWED are fields where Jira doesn't allow to set blank value
            if (fieldValue != null || !CommonIntegrationConstants.JIRA_BLANK_NOT_ALLOWED.contains(fieldMapping.External_Field_Name__c)) {
                if (fieldMapping.External_Field_Name__c.equalsIgnoreCase(CommonIntegrationConstants.DESCRIPTION)) {
                    fieldValue = fieldValue == null ? '' : (String) fieldValue;
                }
                fields.put(fieldMapping.External_Field_Name__c, fieldValue);
            }
        }
        JiraIssueInputBean.Issuetype issueType = new JiraIssueInputBean.Issuetype();
        issueType.id = externalRecordType;
        fields.put(CommonIntegrationConstants.ISSUETYPE_STRING, issueType);
        inputBean.fields = fields;
        return inputBean;
    }

    private static Object getFieldValue(FieldMapping__c fieldMapping, sObject record, Object fieldValue) {
        // Store email address of User
        if (fieldMapping.External_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.USER_TXT)) {
            fieldValue = record.getSObject(fieldMapping.Salesforce_Field_Name__c.replace('__c', '__r')).get(CommonIntegrationConstants.EMAIL);
        } else if (fieldMapping.Salesforce_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.REFERENCE_STRING)) {
            // store external ID in fieldValue.
            fieldValue = record.getSObject(fieldMapping.Salesforce_Field_Name__c.replace('__c', '__r'))
                .get(CommonIntegrationConstants.COPADO_EXTERNAL_ID_FIELD);
            if (fieldValue != null && ((String) fieldValue).isNumeric()) {
                fieldValue = Integer.valueOf(fieldValue);
            }
        } else if (
            fieldMapping.Salesforce_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.PICKLIST_STRING) &&
            fieldMapping.Field_Value_Mappings__r != null
        ) {
            fieldValue = castToJiraPicklistValue(fieldMapping.Field_Value_Mappings__r, (String) fieldValue);
        }
        if (CommonIntegrationConstants.JIRA_REFERENCE_FIELDS.containsKey(fieldMapping.External_Field_Type__c.toLowerCase())) {
            // Will be passed as JSON Object
            Map<String, Object> jiraRef = new Map<String, Object>();
            jiraRef.put(CommonIntegrationConstants.JIRA_REFERENCE_FIELDS.get(fieldMapping.External_Field_Type__c), String.valueOf(fieldValue));
            fieldValue = jiraRef;
        } else if (fieldMapping.External_Field_Name__c.equalsIgnoreCase(CommonIntegrationConstants.FIX_VERSIONS)) {
            Map<String, Object> jiraRef = new Map<String, Object>();
            jiraRef.put('id', String.valueOf(fieldValue));
            fieldValue = new List<Object>{ jiraRef };
        } else if (fieldMapping.External_Field_Name__c.equalsIgnoreCase(CommonIntegrationConstants.DESCRIPTION)) {
            fieldValue = (String) fieldValue;
        } else if (
            fieldMapping.Salesforce_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.REFERENCE_STRING) && // // Referance Fields
            !CommonIntegrationConstants.JIRA_PRIMITIVE_TYPES.contains(fieldMapping.External_Field_Type__c.toLowerCase()) &&
            !fieldMapping.External_Field_Name__c.startsWithIgnoreCase(CommonIntegrationConstants.CUSTOMFIELD_NAME)
        ) {
            Map<String, Object> jiraRef = new Map<String, Object>();
            jiraRef.put('id', String.valueOf(fieldValue));
            fieldValue = jiraRef;
        }
        return fieldValue;
    }

    // Convert to Jira picklist value
    public static String castToJiraPicklistValue(List<Field_Value_Mapping__c> valueMappings, String fieldValue) {
        for (Field_Value_Mapping__c valueMapping : valueMappings) {
            if (
                fieldValue != null &&
                valueMapping.Salesforce_Field_Value__c != null &&
                fieldValue.equalsIgnoreCase(valueMapping.Salesforce_Field_Value__c)
            ) {
                return valueMapping.External_Field_Value__c;
            }
        }
        return fieldValue;
    }

    // Convert to copado picklist value
    public static String castToCopadoPicklistValue(List<Field_Value_Mapping__c> valueMappings, String fieldValue) {
        for (Field_Value_Mapping__c valueMapping : valueMappings) {
            if (
                fieldValue != null &&
                valueMapping.Salesforce_Field_Value__c != null &&
                fieldValue.equalsIgnoreCase(valueMapping.External_Field_Value__c)
            ) {
                return valueMapping.Salesforce_Field_Value__c;
            }
        }
        return fieldValue;
    }
    /**
     * Validate if error is due to record or invalid connection/mapping.
     *
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static Boolean isConfigurationException(
        String subscriberCode,
        Copado_Integration__c config,
        ApiException apiException,
        String sobjectName
    ) {
        if (subscriberCode.equalsIgnoreCase(CommonIntegrationConstants.PROVIDER_TYPE_JIRA) && apiException.getStatusCode() == 400) {
            JiraErrorModel jiraError = (JiraErrorModel) JSON.deserialize(apiException.getBody(), JiraErrorModel.class); // Parse error
            Boolean invalidConnection = false;
            invalidConnection = jiraError.errors.isEmpty() ? true : isFieldALMMappingMissing(jiraError.errors.keySet(), config.id, sobjectName);
            return invalidConnection;
        } else {
            return false;
        }
    }
    private static boolean isFieldALMMappingMissing(Set<String> fields, ID configID, String sobjectName) {
        List<FieldMapping__c> mapping = [
            SELECT ID
            FROM FieldMapping__c
            WHERE
                Copado_Integration__c = :configID
                AND External_Field_Name__c IN :fields
                AND Outbound__c = TRUE
                AND Salesforce_Object__c = :sobjectName
            WITH SECURITY_ENFORCED
        ];
        return mapping.isEmpty();
    }
    /**
     * Update Status of Copado_Integration__c to 'Active with Errors'
     */
    public static void deactivateConnection(Copado_Integration__c config) {
        config.Integration_Status__c = CommonIntegrationConstants.ACTIVE_WITH_ERRORS;
        update config;
    }

    public static Integer getFailedRecordCount(Database.UpsertResult[] resultList) {
        Integer totalFailed = 0;
        for (Database.UpsertResult rslt : resultList) {
            if (!rslt.isSuccess()) {
                totalFailed = totalFailed + 1;
            }
        }
        return totalFailed;
    }

    public static String getAllFailedCause(Database.UpsertResult[] resultList) {
        String errorMessage = '';
        for (Database.UpsertResult rslt : resultList) {
            if (!rslt.isSuccess()) {
                errorMessage = errorMessage + rslt.getErrors();
            }
        }
        return errorMessage;
    }
    /**
     *  if Upsert is failed check if error is due to required field if yes then check if
     *  Corresponding mapping present if Mapping doesn't exists then mark object as failed.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static void updateFailedMapping(
        Database.UpsertResult[] resultList,
        List<Sobject> records,
        Copado_Integration__c config,
        String objectName
    ) {
        Integer index = 0;
        Map<String, FieldMapping__c> fieldMappings = fetchCopadoFieldMapping(config.id, objectName);
        Set<String> failedMapping = new Set<String>();
        for (Database.UpsertResult rslt : resultList) {
            if (objectName.equalsIgnoreCase(copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName())) {
                objectName =
                    objectName + getRecordTypeNameById(objectName, ((String) records.get(index).get(CommonIntegrationConstants.RECORD_TYPE_ID)));
            }
            for (Database.Error err : rslt.getErrors()) {
                if (err.getStatusCode() == StatusCode.REQUIRED_FIELD_MISSING && !fieldMappings.keySet().containsAll(err.getFields())) {
                    config.Integration_Status__c = CommonIntegrationConstants.ACTIVE_WITH_ERRORS;
                    failedMapping.add(fieldMappings.get(objectName).Object_Mapping__c);
                }
            }
            index++;
        }
        List<ObjectMapping__c> objMappingTOMarkFailed = new List<ObjectMapping__c>();
        for (String recordID : failedMapping) {
            objMappingTOMarkFailed.add(new ObjectMapping__c(Id = recordID, Status__c = 'Failed'));
        }
        if (!objMappingTOMarkFailed.isEmpty()) {
            performSecureUpdate(objMappingTOMarkFailed, ObjectMapping__c.SObjectType, true);
        }
    }

    public static void performSecureUpdate(List<SObject> records, SObjectType typeToCheck, Boolean allOrNone) {
        try {
            fflib_SecurityUtils.checkObjectIsUpdateable(typeToCheck);
            Database.update(records, allOrNone);
        } catch (fflib_SecurityUtils.CrudException ex) {
            throw new ConnectException(ex.getMessage());
        } catch (fflib_SecurityUtils.FlsException ex) {
            throw new ConnectException(ex.getMessage());
        }
    }
    public static void performSecureInsert(List<SObject> records, SObjectType typeToCheck) {
        try {
            fflib_SecurityUtils.checkObjectIsInsertable(typeToCheck);
            insert records;
        } catch (fflib_SecurityUtils.CrudException ex) {
            throw new ConnectException(ex.getMessage());
        } catch (fflib_SecurityUtils.FlsException ex) {
            throw new ConnectException(ex.getMessage());
        }
    }
    public static void performSecureDelete(List<SObject> records, SObjectType typeToCheck) {
        try {
            fflib_SecurityUtils.checkObjectIsDeletable(typeToCheck);
            delete records;
        } catch (fflib_SecurityUtils.CrudException ex) {
            throw new ConnectException(ex.getMessage());
        } catch (fflib_SecurityUtils.FlsException ex) {
            throw new ConnectException(ex.getMessage());
        }
    }
    public static List<Database.UpsertResult> performSecureUpsert(List<SObject> records, SObjectType typeToCheck, SObjectField field) {
        try {
            fflib_SecurityUtils.checkObjectIsInsertable(typeToCheck);
            fflib_SecurityUtils.checkObjectIsUpdateable(typeToCheck);
            return Database.upsert(records, field, false);
        } catch (fflib_SecurityUtils.CrudException ex) {
            throw new ConnectException(ex.getMessage());
        } catch (fflib_SecurityUtils.FlsException ex) {
            throw new ConnectException(ex.getMessage());
        }
    }

    private static Map<String, FieldMapping__c> fetchCopadoFieldMapping(ID configID, String objectName) {
        Map<String, FieldMapping__c> fieldMappings = new Map<String, FieldMapping__c>();
        for (FieldMapping__c fm : [
            SELECT ID, Object_Mapping__c, Salesforce_Object_Record_Type__c, Salesforce_Object__c
            FROM FieldMapping__c
            WHERE Copado_Integration__c = :configID AND Salesforce_Object__c = :objectName AND Inbound__c = TRUE
            WITH SECURITY_ENFORCED
        ]) {
            if (objectName.equalsIgnoreCase(copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName())) {
                // User story has record type
                fieldMappings.put(fm.Salesforce_Object__c + fm.Salesforce_Object_Record_Type__c, fm);
            } else {
                fieldMappings.put(fm.Salesforce_Object__c, fm);
            }
        }
        return fieldMappings;
    }

    // Field Mapping Map by External Record Type Id
    public static Map<String, FieldMapping__c> getMappingByExternalRecordType(
        Map<String, FieldMapping__c> almFieldMapping,
        String externalRecordtypeId
    ) {
        Map<String, FieldMapping__c> fieldMappingByRecordType = new Map<String, FieldMapping__c>();
        for (String jiraFieldName : almFieldMapping.keySet()) {
            if (almFieldMapping.get(jiraFieldName).External_Object_Record_Type__c == externalRecordTypeId) {
                fieldMappingByRecordType.put(jiraFieldName, almFieldMapping.get(jiraFieldName));
            }
        }
        return fieldMappingByRecordType;
    }

    /**
     * Covert fieldVal into Sobject Reference based on external ID - for ServiceNow
     */
    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    //line 383 is a false positive PMD error since FieldDescribeOptions enum does not have deferred option unlike SObjectDescribeOptions
    //line 391 has to be silent => Eating error for unhandled Jira object reference fields
    public static sObject convertSNOWValueToObjectReference(FieldMapping__c mappingRec, Object fieldVal, Boolean isSalesforceFieldTypeUser) {
        sObject relatedsObj;
        //If lookup field is User then get referenace of user by Email address
        Boolean isExternalFieldTypeReference =
            mappingRec.External_Field_Type__c != null &&
            mappingRec.External_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.REFERENCE_STRING);
        if (!isExternalFieldTypeReference && isSalesforceFieldTypeUser) {
            if (fieldVal != null) {
                relatedsObj = findUserByEmailAddress(String.valueOf(fieldVal));
            }
            return relatedsObj;
        } else if (isExternalFieldTypeReference && fieldVal instanceof Map<String, Object> && null != ((Map<String, Object>) fieldVal).get('value')) {
            fieldVal = ((Map<String, Object>) fieldVal).get('value');
        }
        relatedsObj = handleSObjectReference(copado__User_Story__c.SObjectType, relatedsObj, mappingRec, fieldVal);
        Boolean sObjNotNull = (null != relatedsObj && null != relatedsObj.get('External_ID__c'));
        Boolean extIdNotBlank = String.isNotBlank(String.valueOf(relatedsObj.get('External_ID__c')));
        return (sObjNotNull && extIdNotBlank ? relatedsObj : null);
    }

    /**
     * Covert fieldVal into Sobject Reference based on external ID
     */
    public static SObject convertToObjectReference(FieldMapping__c mappingRec, Object fieldVal) {
        SObject relatedsObj;
        //If lookup field is User then get referenace of user by Email address
        if (mappingRec.External_Field_Type__c != null && mappingRec.External_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.USER_TXT)) {
            fieldVal = ((Map<String, Object>) fieldVal).get(CommonIntegrationConstants.EMAIL_ADDRESS);
            if (fieldVal != null) {
                relatedsObj = findUserByEmailAddress(String.valueOf(fieldVal));
            }
            return relatedsObj;
        } else if (mappingRec.External_Field_Type__c != null && mappingRec.External_Field_Type__c.equalsIgnoreCase('array')) {
            // get ID from array
            if (((List<Object>) fieldVal).size() == 0) {
                // Field is blank
                return null;
            }
            for (Object fieldRecord : (List<Object>) fieldVal) {
                if (fieldRecord instanceof String) {
                    fieldVal = String.valueof(fieldVal).substringBetween('id=', ',');
                } else if (((Map<String, Object>) fieldRecord).get('id') != null) {
                    fieldVal = ((Map<String, Object>) fieldRecord).get('id');
                }
            }
        } else if (fieldVal instanceof Map<String, Object>) {
            fieldVal = ((Map<String, Object>) fieldVal).get('id');
        }
        relatedsObj = handleSObjectReferenceBasedOnType(relatedsObj, mappingRec, fieldVal);
        return relatedsObj != null &&
            relatedsObj.get('External_ID__c') != null &&
            String.isNotBlank(String.valueOf(relatedsObj.get('External_ID__c')))
            ? relatedsObj
            : null;
    }

    private static SObject handleSObjectReferenceBasedOnType(SObject relatedsObj, FieldMapping__c mappingRec, Object fieldVal) {
        if (
            copado__User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .containsKey(mappingRec.Salesforce_Field_Name__c)
        ) {
            relatedsObj = handleSObjectReference(copado__User_Story__c.SObjectType, relatedsObj, mappingRec, fieldVal);
        }
        if (
            copado__User_Story_Task__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .containsKey(mappingRec.Salesforce_Field_Name__c)
        ) {
            relatedsObj = handleSObjectReference(copado__User_Story_Task__c.SObjectType, relatedsObj, mappingRec, fieldVal);
        }
        return relatedsObj;
    }

    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult, PMD.ExcessiveParameterList')
    //line 431 is a false positive PMD error since FieldDescribeOptions enum does not have deferred option unlike SObjectDescribeOptions
    private static SObject handleSObjectReference(SObjectType currentType, SObject relatedsObj, FieldMapping__c mappingRec, Object fieldVal) {
        Schema.DescribeFieldResult f = currentType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(mappingRec.Salesforce_Field_Name__c)
            .getDescribe();
        try {
            for (Schema.SObjectType reference : f.getReferenceTo()) {
                relatedsObj = reference.newSObject();
                relatedsObj.put('External_ID__c', String.valueOf(fieldVal));
                mappingRec.Salesforce_Field_Name__c = f.relationshipname;
            }
        } catch (System.SObjectException invalidCasting) {
            if (currentType == copado__User_Story_Task__c.SObjectType) {
                Integration_Log__c log = new Integration_Log__c();
                log.Error_Message__c = String.valueOf(invalidCasting);
                log.Object_Name__c = copado__User_Story_Task__c.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName();
                performSecureInsert(new List<Integration_Log__c>{ log }, Integration_Log__c.SObjectType);
            }
        }
        return relatedsObj;
    }
    /**
     * return true if Object field mapping is configured otherwise false
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static Boolean isObjectMappingConfigured(String objectName, String configID, String rt, Boolean inbound) {
        String soqlString =
            'Select ID from FieldMapping__c Where Copado_Integration__c =:configID AND' +
            '  Salesforce_Object__c =:objectName AND Salesforce_Object_Record_Type__c = :rt' +
            ' AND {0} WITH SECURITY_ENFORCED';
        if (inbound) {
            soqlString = String.format(soqlString, new List<String>{ 'Inbound__c = true' });
        } else {
            soqlString = String.format(soqlString, new List<String>{ 'Outbound__c = true' });
        }

        List<FieldMapping__c> records = Database.query(String.escapeSingleQuotes(soqlString));
        return records.isEmpty() ? false : true;
    }
    /**
     * Create ObjectMapping__c & FieldMapping__c records for Project
     */
    public static void createDefaultJiraProjectMapping(String configId) {
        ObjectMapping__c objMaping = new ObjectMapping__c(Copado_Integration__c = configId);
        objMaping.Salesforce_Object_Name__c = copado__Project__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        objMaping.External_Object_Name__c = 'project';
        objMaping.Status__c = CommonIntegrationConstants.MAPPED;
        fflib_SecurityUtils.checkObjectIsInsertable(copado__Project__c.SObjectType);
        performSecureInsert(new List<ObjectMapping__c>{ objMaping }, ObjectMapping__c.SObjectType);

        List<FieldMapping__c> fieldMappingRecords = new List<FieldMapping__c>();
        FieldMapping__c nameMapping = new FieldMapping__c(
            Copado_Integration__c = configId,
            Object_Mapping__c = objMaping.id,
            Salesforce_Field_Name__c = 'Name',
            Salesforce_Field_Type__c = CommonIntegrationConstants.STRING_TYPE,
            External_Field_Name__c = CommonIntegrationConstants.NAME,
            External_Field_Type__c = CommonIntegrationConstants.TEXT,
            Inbound__c = true,
            Outbound__c = true,
            Status__c = CommonIntegrationConstants.MAPPED
        );

        fieldMappingRecords.add(nameMapping);

        FieldMapping__c descriptionMapping = new FieldMapping__c(
            Copado_Integration__c = configId,
            Object_Mapping__c = objMaping.id,
            Salesforce_Field_Name__c = 'copado__Description__c',
            Salesforce_Field_Type__c = CommonIntegrationConstants.TEXTAREA,
            External_Field_Name__c = CommonIntegrationConstants.DESCRIPTION,
            External_Field_Type__c = CommonIntegrationConstants.TEXT,
            Inbound__c = true,
            Outbound__c = true,
            Status__c = CommonIntegrationConstants.MAPPED
        );

        fieldMappingRecords.add(descriptionMapping);

        FieldMapping__c idMapping = new FieldMapping__c(
            Copado_Integration__c = configId,
            Object_Mapping__c = objMaping.id,
            Salesforce_Field_Name__c = CommonIntegrationConstants.COPADO_EXTERNAL_ID_FIELD,
            Salesforce_Field_Type__c = CommonIntegrationConstants.STRING_TYPE,
            External_Field_Name__c = CommonIntegrationConstants.ID_STRING,
            External_Field_Type__c = CommonIntegrationConstants.TEXT,
            Inbound__c = true,
            Outbound__c = false,
            Status__c = CommonIntegrationConstants.MAPPED
        );

        fieldMappingRecords.add(idMapping);

        performSecureInsert(fieldMappingRecords, FieldMapping__c.SObjectType);
    }

    private static SObject findUserByEmailAddress(String email) {
        List<User> users = [SELECT ID FROM User WHERE Email = :email WITH SECURITY_ENFORCED LIMIT 1];
        return users.isEmpty() ? null : users.get(0);
    }

    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    //line 519 is a false positive PMD error since FieldDescribeOptions enum does not have deferred option unlike SObjectDescribeOptions
    public static Map<String, String> getFields(String sObjectName, Boolean includeReferences, Boolean updateatableOnly) {
        Map<String, String> result = new Map<String, String>();
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(sObjectName)
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();

            if (describe.isAccessible() && ((updateatableOnly && describe.isUpdateable()) || !updateatableOnly)) {
                //below line is to prevent duplicate field issue on package field api name conflict with a customer org
                result.put(describe.getName().replace(CommonIntegrationConstants.ns, ''), describe.getLabel());
            }
        }
        return result;
    }

    public static Map<ID, SObject> querySobjectsByExternalID(String externalID, String objectName) {
        Map<Id, SObject> records = new Map<Id, SObject>(
            (List<SObject>) Database.query(
                String.format(
                    CommonIntegrationConstants.QUERY_TEMPLATE,
                    new List<String>{
                        String.join(new List<String>(getFields(objectName, true, true).keySet()), ','),
                        objectName,
                        ConnectSubscriberFactory.objectExternalFieldMapping.get(objectName) +
                        ' = \'' +
                        externalID +
                        '\''
                    }
                )
            )
        );
        return records;
    }

    // Convert DDMMYYYY string date to Date
    public static Date convertToDate(String sprintDate) {
        sprintDate = sprintDate.left(8);
        return Date.newInstance(
            Integer.valueOf(sprintDate.right(4)),
            Integer.valueOf(sprintDate.substring(2, 4)),
            Integer.valueOf(sprintDate.left(2))
        );
    }

    //Get ServiceNowStoryInputBean
    public static ServiceNowStoryInputBean getServiceNowUpdateStoryInputBean(Map<String, FieldMapping__c> copadoFieldMapping, sObject record) {
        ServiceNowStoryInputBean inputBean = new ServiceNowStoryInputBean();
        Map<String, Object> fields = new Map<String, Object>();
        for (String salesforceFieldName : copadoFieldMapping.keySet()) {
            FieldMapping__c fieldMapping = copadoFieldMapping.get(salesforceFieldName);
            Object fieldValue = record.get(salesforceFieldName);
            if (fieldValue != null) {
                if (
                    fieldMapping.Salesforce_Field_Type__c.equalsIgnoreCase(CommonIntegrationConstants.PICKLIST_STRING) &&
                    fieldMapping.Field_Value_Mappings__r != null
                ) {
                    fieldValue = ConnectUtilities.castToJiraPicklistValue(fieldMapping.Field_Value_Mappings__r, (String) fieldValue);
                }
                fields.put(fieldMapping.External_Field_Name__c, castToServiceNowValue(fieldValue, fieldMapping.Salesforce_Field_Type__c));
            }
        }
        inputBean.fields = fields;
        return inputBean;
    }

    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    //line 572, 577 is a false positive PMD error since FieldDescribeOptions enum does not have deferred option unlike SObjectDescribeOptions
    public static boolean isSalesforceFieldTypeUser(String salesforceObject, String salesforceField) {
        Boolean result = false;
        Schema.DescribeFieldResult salesforceFieldResult = Schema.getGlobalDescribe()
            .get(salesforceObject)
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(salesforceField.replace('__r', '__c'))
            .getDescribe();
        List<Schema.SObjectType> salesforceFieldTypes = salesforceFieldResult.getReferenceTo();
        for (Schema.SObjectType salesforceFieldType : salesforceFieldTypes) {
            if (salesforceFieldType == User.SObjectType) {
                result = true;
                break;
            }
        }
        return result;
    }

    /**
     * Retrive Object mapping for Configuration
     */
    public static Map<String, String> getObjectMapping(ID configId) {
        Map<String, String> objMapping = new Map<String, String>();
        for (ObjectMapping__c rec : [
            SELECT ID, Salesforce_Object_Name__c, External_Object_Name__c, Status__c
            FROM ObjectMapping__c
            WHERE Copado_Integration__c = :configId
            WITH SECURITY_ENFORCED
        ]) {
            objMapping.put(rec.Salesforce_Object_Name__c, rec.External_Object_Name__c);
        }
        return objMapping;
    }
    
    public static String addSingleQuotes(String param){
        return '\'' + param + '\'';
    }
}