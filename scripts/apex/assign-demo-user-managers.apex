// sf apex run --file scripts/apex/assign-demo-user-managers.apex --target-org pharma-prod
Integer assigned = TerritoryModuleSeed.assignDemoUserManagersFromOrg();
System.debug('Assigned ' + assigned + ' demo MR manager links.');
