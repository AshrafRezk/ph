TerritoryModuleSeed.SeedResult userResult = TerritoryModuleSeed.seedAdditionalProductLineUsersAndProducts();
System.debug(userResult.message);
ChemipharmAppPersonaSeed.SeedResult personaResult = ChemipharmAppPersonaSeed.assignDemoPersonas();
System.debug(personaResult.message);
