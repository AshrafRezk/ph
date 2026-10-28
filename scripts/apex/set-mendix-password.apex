Id uid = [SELECT Id FROM User WHERE Username = 'mendix.api@zetapharma.com' LIMIT 1].Id;
System.setPassword(uid, 'REPLACE_WITH_MENDIX_PASSWORD');
System.debug('Password set for ' + uid);
