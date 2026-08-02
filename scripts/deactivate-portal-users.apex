List<User> portalUsers = [
    SELECT Id, IsActive
    FROM User
    WHERE Contact.Account.CreatedDate < TODAY
      AND IsActive = true
];
for (User u : portalUsers) {
    u.IsActive = false;
}
if (!portalUsers.isEmpty()) {
    update portalUsers;
}
System.debug('Deactivated portal users: ' + portalUsers.size());
