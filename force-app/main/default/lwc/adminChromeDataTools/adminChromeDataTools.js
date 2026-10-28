import { LightningElement } from 'lwc';

const EXTENSIONS = [
    {
        id: 'inspector',
        name: 'Salesforce Inspector Reloaded',
        blurb: 'Inspect fields, run SOQL, export data, and jump to setup pages from any record.',
        url: 'https://chromewebstore.google.com/detail/salesforce-inspector-relo/hpckbmvgliadnfhcgncipofcnlnbfooo'
    },
    {
        id: 'dataloader',
        name: 'Salesforce Data Loader (desktop)',
        blurb: 'Bulk load from CSV. Run every load in a sandbox first and keep the success and error files.',
        url: 'https://developer.salesforce.com/tools/data-loader'
    }
];

const QUERIES = [
    {
        id: 'accounts',
        title: 'Accounts (sample)',
        soql: "SELECT Id, Name, RecordType.Name, BillingCity, Is_Speaker__c FROM Account WHERE Name LIKE '%Training%' LIMIT 200"
    },
    {
        id: 'users',
        title: 'Active users',
        soql: "SELECT Id, Name, Username, Title, IsActive, Profile.Name FROM User WHERE IsActive = true ORDER BY Name LIMIT 200"
    },
    {
        id: 'uta',
        title: 'User territory assignments',
        soql: 'SELECT Id, UserId, User.Name, Territory2Id, Territory2.Name, RoleInTerritory2 FROM UserTerritory2Association WHERE IsActive = true LIMIT 500'
    },
    {
        id: 'ratings',
        title: 'Account territory ratings',
        soql: 'SELECT Id, Account__c, Account__r.Name, Territory__c, Classification__c, Is_Speaker__c FROM Account_Territory_Rating__c LIMIT 200'
    },
    {
        id: 'products',
        title: 'Product territory alignments',
        soql: 'SELECT Id, Product__c, Product__r.Name, Territory__c, Territory__r.Name FROM Product_Territory_Alignment__c LIMIT 200'
    },
    {
        id: 'field-requests',
        title: 'Field requests',
        soql: 'SELECT Id, Name, Status__c, Kind__c, Type__c, Account__c, CreatedDate FROM Field_Request__c ORDER BY CreatedDate DESC LIMIT 100'
    }
];

const DML = [
    {
        id: 'insert',
        title: 'Insert',
        body: 'Creates new rows. Use when the record does not exist yet. Failures leave no partial Id. Prefer external Id upsert when syncing from Excel.'
    },
    {
        id: 'update',
        title: 'Update',
        body: 'Changes existing rows by Id. You must supply Id. Blank fields are not cleared unless you send null explicitly.'
    },
    {
        id: 'upsert',
        title: 'Upsert',
        body: 'Insert or update by External Id. Best for territory ratings and product alignments from files. Match key must be unique.'
    },
    {
        id: 'delete',
        title: 'Delete',
        body: 'Moves rows to the Recycle Bin for 15 days, then they are gone for good. Never delete master accounts or live plan cycles; set them inactive instead.'
    }
];

export default class AdminChromeDataTools extends LightningElement {
    get extensions() {
        return EXTENSIONS;
    }
    get queries() {
        return QUERIES;
    }
    get dmlDocs() {
        return DML;
    }
}
