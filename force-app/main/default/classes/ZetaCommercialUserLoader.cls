/**
 * Upserts the commercial employee file and sets each password to FirstName + '@2026!'.
 * Welcome email is suppressed. The same password rule is then applied to every other
 * active standard user, except the running user and integration users.
 */
public without sharing class ZetaCommercialUserLoader implements Queueable {
    public static final String RESOURCE_NAME = 'ZetaCommercialUsers';
    public static final String DELTA_RESOURCE_NAME = 'ZetaCommercialUserDelta';
    public static final String PASSWORD_SUFFIX = '@2026!';
    public static final Integer CHUNK_SIZE = 15;

    @TestVisible private static String testEmployeesJson;
    @TestVisible private static String testDeltaJson;
    @TestVisible private static Boolean skipChain = false;

    private Integer employeeIndex;
    private String phase;
    private Id lastUserId;
    private Integer failureCount;
    private List<String> errors;

    public ZetaCommercialUserLoader() {
        this(0, 'employees', null, 0, new List<String>());
    }

    private ZetaCommercialUserLoader(
        Integer employeeIndex,
        String phase,
        Id lastUserId,
        Integer failureCount,
        List<String> errors
    ) {
        this.employeeIndex = employeeIndex == null ? 0 : employeeIndex;
        this.phase = String.isBlank(phase) ? 'employees' : phase;
        this.lastUserId = lastUserId;
        this.failureCount = failureCount == null ? 0 : failureCount;
        this.errors = errors == null ? new List<String>() : errors;
    }

    public static Id start() {
        return System.enqueueJob(new ZetaCommercialUserLoader());
    }

    /**
     * Upserts the employee batch only. New users receive FirstName@2026!.
     * Existing users keep their password, and other active users are left alone.
     */
    public static Id startDelta() {
        return System.enqueueJob(new ZetaCommercialUserLoader(0, 'delta', null, 0, new List<String>()));
    }

    @TestVisible
    static void executePhase(String phaseName) {
        new ZetaCommercialUserLoader(0, phaseName, null, 0, new List<String>()).execute(null);
    }

    public static String passwordFor(String nameOrFirst) {
        String token = nameOrFirst == null ? '' : nameOrFirst.trim();
        if (token.contains(' ')) {
            token = token.substringBefore(' ');
        }
        token = token.replaceAll('[^A-Za-z]', '');
        if (String.isBlank(token)) {
            token = 'User';
        }
        return token + PASSWORD_SUFFIX;
    }

    public void execute(QueueableContext context) {
        if (phase == 'delta') {
            loadDeltaChunk();
            return;
        }
        if (phase == 'deltaManagers') {
            applyManagers(deltaEmployees());
            System.debug(
                'Zeta employee delta finished. failures=' + failureCount + ' sample=' + String.join(errors, ' | ')
            );
            return;
        }
        if (phase == 'managers') {
            applyManagers(employees());
            enqueue(new ZetaCommercialUserLoader(0, 'passwords', null, failureCount, errors));
            return;
        }
        if (phase == 'passwords') {
            applyPasswordsToActiveUsers();
            return;
        }
        loadEmployeeChunk();
    }

    private void loadEmployeeChunk() {
        List<Object> employees = employees();
        Integer endIndex = Math.min(employeeIndex + CHUNK_SIZE, employees.size());
        if (employeeIndex >= employees.size()) {
            enqueue(new ZetaCommercialUserLoader(0, 'managers', null, failureCount, errors));
            return;
        }

        List<EmployeeRow> chunk = new List<EmployeeRow>();
        Set<String> usernames = new Set<String>();
        for (Integer i = employeeIndex; i < endIndex; i++) {
            EmployeeRow row = new EmployeeRow((Map<String, Object>) employees[i]);
            if (String.isBlank(row.email) || String.isBlank(row.name)) {
                remember(row.email + ': missing name or email');
                continue;
            }
            chunk.add(row);
            usernames.add(row.email);
        }

        Map<String, User> existingByUsername = new Map<String, User>();
        if (!usernames.isEmpty()) {
            for (User existing : [
                SELECT Id, Username, Profile.Name
                FROM User
                WHERE Username IN :usernames
            ]) {
                existingByUsername.put(existing.Username.toLowerCase(), existing);
            }
        }

        Id standardProfileId = standardProfileId();
        List<User> toInsert = new List<User>();
        List<User> toUpdate = new List<User>();
        List<String> insertPasswords = new List<String>();
        List<String> updatePasswords = new List<String>();

        for (EmployeeRow row : chunk) {
            User existing = existingByUsername.get(row.email);
            String password = passwordFor(row.name);
            if (existing == null) {
                toInsert.add(newUser(row, standardProfileId));
                insertPasswords.add(password);
            } else {
                User updateRow = newUser(row, null);
                updateRow.Id = existing.Id;
                toUpdate.add(updateRow);
                updatePasswords.add(password);
            }
        }

        Database.DMLOptions options = new Database.DMLOptions();
        options.EmailHeader.triggerUserEmail = false;
        options.EmailHeader.triggerOtherEmail = false;
        options.optAllOrNone = false;

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, options);
            rememberDml(results, toInsert, insertPasswords, true);
        }
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, options);
            rememberDml(results, toUpdate, updatePasswords, false);
        }

        enqueue(new ZetaCommercialUserLoader(endIndex, 'employees', null, failureCount, errors));
    }

    private void loadDeltaChunk() {
        List<Object> rows = deltaEmployees();
        Integer endIndex = Math.min(employeeIndex + CHUNK_SIZE, rows.size());
        if (employeeIndex >= rows.size()) {
            enqueue(new ZetaCommercialUserLoader(0, 'deltaManagers', null, failureCount, errors));
            return;
        }

        List<EmployeeRow> chunk = new List<EmployeeRow>();
        Set<String> usernames = new Set<String>();
        for (Integer i = employeeIndex; i < endIndex; i++) {
            EmployeeRow row = new EmployeeRow((Map<String, Object>) rows[i]);
            if (String.isBlank(row.email) || String.isBlank(row.name)) {
                remember(row.email + ': missing name or email');
                continue;
            }
            chunk.add(row);
            usernames.add(row.email);
        }

        Set<String> codes = new Set<String>();
        for (EmployeeRow row : chunk) {
            if (String.isNotBlank(row.code)) {
                codes.add(row.code);
            }
        }
        Map<String, User> existingByUsername = new Map<String, User>();
        Map<String, User> existingByCode = new Map<String, User>();
        if (!usernames.isEmpty() || !codes.isEmpty()) {
            for (User existing : [
                SELECT Id, Username, EmployeeNumber
                FROM User
                WHERE Username IN :usernames OR EmployeeNumber IN :codes
            ]) {
                if (existing.Username != null) {
                    existingByUsername.put(existing.Username.toLowerCase(), existing);
                }
                if (String.isNotBlank(existing.EmployeeNumber) && !existingByCode.containsKey(existing.EmployeeNumber)) {
                    existingByCode.put(existing.EmployeeNumber, existing);
                }
            }
        }

        Id standardProfileId = standardProfileId();
        List<User> toInsert = new List<User>();
        List<User> toUpdate = new List<User>();
        List<String> insertPasswords = new List<String>();

        for (EmployeeRow row : chunk) {
            User existing = existingByCode.get(row.code);
            if (existing == null) {
                existing = existingByUsername.get(row.email);
            }
            if (existing == null) {
                toInsert.add(newUser(row, standardProfileId));
                insertPasswords.add(passwordFor(row.name));
            } else {
                User updateRow = newUser(row, null);
                updateRow.Id = existing.Id;
                toUpdate.add(updateRow);
            }
        }

        Database.DMLOptions options = new Database.DMLOptions();
        options.EmailHeader.triggerUserEmail = false;
        options.EmailHeader.triggerOtherEmail = false;
        options.optAllOrNone = false;

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, options);
            rememberDml(results, toInsert, insertPasswords, true);
        }
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, options);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    remember(toUpdate[i].Username + ': ' + results[i].getErrors()[0].getMessage());
                }
            }
        }

        enqueue(new ZetaCommercialUserLoader(endIndex, 'delta', null, failureCount, errors));
    }

    private void applyManagers(List<Object> sourceRows) {
        Set<String> codes = new Set<String>();
        for (Object raw : sourceRows) {
            EmployeeRow row = new EmployeeRow((Map<String, Object>) raw);
            if (String.isNotBlank(row.code)) {
                codes.add(row.code);
            }
            if (String.isNotBlank(row.managerCode)) {
                codes.add(row.managerCode);
            }
        }
        Map<String, Id> userIdByCode = new Map<String, Id>();
        if (!codes.isEmpty()) {
            for (User employee : [
                SELECT Id, EmployeeNumber
                FROM User
                WHERE EmployeeNumber IN :codes
            ]) {
                userIdByCode.put(employee.EmployeeNumber, employee.Id);
            }
        }

        List<User> updates = new List<User>();
        for (Object raw : sourceRows) {
            EmployeeRow row = new EmployeeRow((Map<String, Object>) raw);
            if (String.isBlank(row.code)) {
                continue;
            }
            Id userId = userIdByCode.get(row.code);
            if (userId == null) {
                continue;
            }
            if (String.isBlank(row.managerCode)) {
                if (phase == 'deltaManagers') {
                    updates.add(new User(Id = userId, ManagerId = null));
                }
                continue;
            }
            Id managerId = userIdByCode.get(row.managerCode);
            if (managerId == null || userId == managerId) {
                continue;
            }
            updates.add(new User(Id = userId, ManagerId = managerId));
        }

        for (Integer start = 0; start < updates.size(); start += 100) {
            Integer endAt = Math.min(start + 100, updates.size());
            List<User> slice = new List<User>();
            for (Integer i = start; i < endAt; i++) {
                slice.add(updates[i]);
            }
            Database.SaveResult[] results = Database.update(slice, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    remember(slice[i].Id + ': manager ' + results[i].getErrors()[0].getMessage());
                }
            }
        }
    }

    private void applyPasswordsToActiveUsers() {
        Set<String> onlyUsernames = testUsernames();
        List<User> users;
        if (!onlyUsernames.isEmpty()) {
            users = [
                SELECT Id, FirstName, Username, Profile.Name
                FROM User
                WHERE IsActive = TRUE AND Username IN :onlyUsernames
            ];
            setPasswords(users);
            return;
        }
        if (lastUserId == null) {
            users = [
                SELECT Id, FirstName, Username, Profile.Name
                FROM User
                WHERE IsActive = TRUE AND UserType = 'Standard' AND Id != :UserInfo.getUserId()
                ORDER BY Id
                LIMIT 100
            ];
        } else {
            users = [
                SELECT Id, FirstName, Username, Profile.Name
                FROM User
                WHERE IsActive = TRUE
                    AND UserType = 'Standard'
                    AND Id != :UserInfo.getUserId()
                    AND Id > :lastUserId
                ORDER BY Id
                LIMIT 100
            ];
        }
        Id cursor = lastUserId;
        for (User userRecord : users) {
            cursor = userRecord.Id;
        }
        setPasswords(users);
        if (users.size() == 100) {
            enqueue(new ZetaCommercialUserLoader(0, 'passwords', cursor, failureCount, errors));
            return;
        }
        System.debug(
            'Zeta user load finished. failures=' + failureCount + ' sample=' + String.join(errors, ' | ')
        );
    }

    private static User newUser(EmployeeRow row, Id profileId) {
        String firstName = row.name.contains(' ') ? row.name.substringBefore(' ') : row.name;
        String lastName = row.name.contains(' ') ? row.name.substringAfter(' ').trim() : row.name;
        if (lastName.length() > 80) {
            lastName = lastName.substring(0, 80);
        }
        User userRecord = new User(
            FirstName = trimTo(firstName, 40),
            LastName = String.isBlank(lastName) ? firstName : lastName,
            Email = row.email,
            Username = row.email,
            Title = trimTo(row.title, 80),
            Department = trimTo(row.department, 80),
            Division = trimTo(row.line, 80),
            EmployeeNumber = trimTo(row.code, 20),
            CompanyName = 'Zeta Pharma',
            Alias = aliasFor(firstName, lastName),
            CommunityNickname = trimTo('z' + row.code, 40),
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        if (profileId != null) {
            userRecord.ProfileId = profileId;
        }
        if (String.isNotBlank(row.mobile)) {
            userRecord.MobilePhone = trimTo(row.mobile, 40);
        }
        return userRecord;
    }

    private void rememberDml(Database.SaveResult[] results, List<User> rows, List<String> passwords, Boolean inserted) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                remember(rows[i].Username + ': ' + results[i].getErrors()[0].getMessage());
                continue;
            }
            Id userId = inserted ? results[i].getId() : rows[i].Id;
            try {
                System.setPassword(userId, passwords[i]);
            } catch (Exception ex) {
                remember(rows[i].Username + ': ' + ex.getMessage());
            }
        }
    }

    private void setPasswords(List<User> users) {
        for (User userRecord : users) {
            if (isIntegration(userRecord)) {
                continue;
            }
            try {
                System.setPassword(userRecord.Id, passwordFor(userRecord.FirstName));
            } catch (Exception ex) {
                remember(userRecord.Username + ': ' + ex.getMessage());
            }
        }
    }

    private Set<String> testUsernames() {
        Set<String> usernames = new Set<String>();
        if (!Test.isRunningTest() || String.isBlank(testEmployeesJson)) {
            return usernames;
        }
        for (Object raw : employees()) {
            EmployeeRow row = new EmployeeRow((Map<String, Object>) raw);
            if (String.isNotBlank(row.email)) {
                usernames.add(row.email);
            }
        }
        return usernames;
    }

    @TestVisible
    private static Boolean isIntegration(User userRecord) {
        String profileName = userRecord.Profile == null ? '' : userRecord.Profile.Name;
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        return profileName.contains('Integration')
            || profileName.contains('API Only')
            || username.endsWith('.ext');
    }

    private static Id standardProfileId() {
        return [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
    }

    private List<Object> employees() {
        return readRows(testEmployeesJson, RESOURCE_NAME);
    }

    private List<Object> deltaEmployees() {
        return readRows(testDeltaJson, DELTA_RESOURCE_NAME);
    }

    private static List<Object> readRows(String injected, String resourceName) {
        String body = injected;
        if (body == null) {
            body = [SELECT Body FROM StaticResource WHERE Name = :resourceName LIMIT 1].Body.toString();
        }
        return (List<Object>) JSON.deserializeUntyped(body);
    }

    private void remember(String message) {
        failureCount++;
        if (errors.size() < 40) {
            errors.add(message);
        }
    }

    private void enqueue(ZetaCommercialUserLoader nextJob) {
        if (skipChain) {
            return;
        }
        System.enqueueJob(nextJob);
    }

    private static String aliasFor(String firstName, String lastName) {
        String raw = (firstName + lastName).replaceAll('[^A-Za-z0-9]', '');
        if (String.isBlank(raw)) {
            raw = 'zetauser';
        }
        return raw.length() > 8 ? raw.substring(0, 8) : raw;
    }

    private static String trimTo(String value, Integer maxLength) {
        String text = value == null ? '' : value.trim();
        return text.length() > maxLength ? text.substring(0, maxLength) : text;
    }

    private class EmployeeRow {
        public String code;
        public String name;
        public String title;
        public String department;
        public String line;
        public String managerCode;
        public String email;
        public String mobile;

        public EmployeeRow(Map<String, Object> raw) {
            code = text(raw.get('code'));
            name = text(raw.get('name'));
            title = text(raw.get('title'));
            department = text(raw.get('department'));
            line = text(raw.get('line'));
            managerCode = text(raw.get('managerCode'));
            email = text(raw.get('email')).toLowerCase();
            mobile = text(raw.get('mobile'));
        }

        private String text(Object value) {
            return value == null ? '' : String.valueOf(value).trim();
        }
    }
}
