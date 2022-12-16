public with sharing class AssetManagementBatch implements Database.Batchable<SObject>, Database.Stateful {

    final DateTime endDate = getUTCDateTime(System.now().addDays(5)); //End Date for the query
    Map<Id, Set<String>> needsToProcessAssetIds; //statefull attribute for the storing the Assets with Account

    public AssetManagementBatch () {
        needsToProcessAssetIds = new Map<Id, Set<String>>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        String query  = 'SELECT Id, Name, LifecycleStartDate, LifecycleEndDate, RenewalTerm, RenewalTermUnit, AccountId FROM Asset where HasLifecycleManagement = TRUE and LifecycleEndDate =: endDate Order by AccountId';
        system.debug('<<<<<<<Batch Query>>>>>>>'+ query);
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Asset> assetList) {
        Set<String> accountIds = new Set<String>();
        Map<Id, Set<String>> accountWithAssetIdsMap = new Map<Id, Set<String>>();
        Map<String, Integer> accountWithAssetLengthMap = new Map<String, Integer>();
        //Creating the Map to process the Renew and add the existing assets the map to compare them
        for(Asset a : assetList) {
            accountIds.add(a.AccountId);
            if(!accountWithAssetIdsMap.containsKey(a.accountId)){
                Set<String> assetIds = new Set<String>{a.Id};
                accountWithAssetIdsMap.put(a.AccountId, assetIds);
                if(needsToProcessAssetIds.containsKey(a.accountId)){
                    accountWithAssetIdsMap.get(a.accountId).addAll(needsToProcessAssetIds.get(a.accountId));
                }
            }
            else{
                accountWithAssetIdsMap.get(a.AccountId).add(a.Id);
            }
        }

        // AggregateResult is used to compare the Assets on the Account with the size
        // If the size does not match remove it from the map
        for(AggregateResult a : [SELECT AccountId, Count(Id) assets FROM Asset where HasLifecycleManagement = TRUE AND LifecycleEndDate =: endDate and AccountId IN: accountIds  group by AccountId]){
            Integer assetsSize = Integer.valueOf(a.get('assets'));
            String accountId = String.valueOf(a.get('AccountId'));
            accountWithAssetLengthMap.put(accountId, assetsSize);
            if(accountWithAssetIdsMap.get(accountId).size() != assetsSize){
                needsToProcessAssetIds.put(accountId, accountWithAssetIdsMap.get(accountId));
                accountWithAssetIdsMap.remove(accountId);
            }
        }

        for(Id accountId : accountWithAssetIdsMap.keySet()){
            List<String> assetIds = new List<String>(accountWithAssetIdsMap.get(accountId));
            List<String> assetIdsToProcess = new List<String>();
            //Splitting the list if there is more than 100 elements
            for(String assetId : assetIds){
                assetIdsToProcess.add(assetId);
                if(assetIdsToProcess.size() == 100){
                    AssetManagementController.renewAssetsAPI(assetIdsToProcess);
                    assetIdsToProcess = new List<String>();
                }
            }
            //This is for the last set of assets If there is any
            if(!assetIdsToProcess.isEmpty()) {
                AssetManagementController.renewAssetsAPI(assetIdsToProcess);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        
    }

    public DateTime getUTCDateTime(DateTime dt){
        Datetime gmtDateTime = Datetime.newInstanceGmt(
            dt.year(),
            dt.month(),
            dt.day(),
            23,
            59,
            59
        );
        return gmtDateTime;
    }
}
