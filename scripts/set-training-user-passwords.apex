List<User> users = [
    SELECT Id, Name, FirstName, LastName, Username, Email, IsActive
    FROM User
    WHERE Username IN (
        'bassant.bahaaelden@zetapharma.net',
        'Nada.wael@zetapharma.net',
        'Omar.mohsen@zetapharma.net',
        'gassem.gamal@zetapharma.net',
        'mohamed.rafek@zeta-pharma.com',
        'aya.adel@zeta-pharma.com',
        'manar.saleh@zeta-pharma.com',
        'hamsa.diaaeldin@zeta-pharma.com',
        'david.badie@zeta-pharma.com'
    )
];

System.debug('Found ' + users.size() + ' training users.');
for (User u : users) {
    if (!u.IsActive) {
        System.debug('SKIP inactive: ' + u.Username);
        continue;
    }
    String pwd = u.FirstName + '@demo1';
    try {
        System.setPassword(u.Id, pwd);
        System.debug('OK ' + u.Name + ' | ' + u.Username + ' | ' + u.Email + ' | ' + pwd);
    } catch (Exception e) {
        System.debug('FAIL ' + u.Name + ' | ' + u.Username + ' | ' + e.getMessage());
    }
}
