/**
 * Edit User screen in Territory Management: every HR / job / login field SFE maintains, the
 * person's current organogram seats, and their scheduled and recent seat changes.
 * HR date fields are optional per org (prod has Hire_Date__c only), so they are read and written
 * only when the field exists.
 */
public without sharing class UserEditorController {
    private static final List<String> OPTIONAL_DATES = new List<String>{
        'Hire_Date__c',
        'Resignation_Date__c',
        'Last_Work_Day__c'
    };

    public class Seat {
        @AuraEnabled public Id territoryId;
        @AuraEnabled public String territoryName;
        @AuraEnabled public String externalId;
        @AuraEnabled public String territoryType;
        @AuraEnabled public String role;
    }

    public class UserDetails {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
        @AuraEnabled public String division;
        @AuraEnabled public String employeeNumber;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String phone;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String managerName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String profileName;
        @AuraEnabled public Date hireDate;
        @AuraEnabled public Date resignationDate;
        @AuraEnabled public Date lastWorkDay;
        @AuraEnabled public List<String> dateFields;
        @AuraEnabled public List<Seat> seats;
        @AuraEnabled public List<SeatChangeService.ScheduledRow> scheduled;
        @AuraEnabled public List<SeatChangeService.ScheduledRow> history;
    }

    public class UserForm {
        @AuraEnabled public Id userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
        @AuraEnabled public String division;
        @AuraEnabled public String employeeNumber;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String phone;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String hireDate;
        @AuraEnabled public String resignationDate;
        @AuraEnabled public String lastWorkDay;
    }

    @AuraEnabled
    public static UserDetails getUserEditDetails(Id userId) {
        if (userId == null) {
            throw new AuraHandledException('User is required.');
        }
        List<String> dateFields = availableDateFields();
        String soql =
            'SELECT Id, Name, FirstName, LastName, Email, Username, Title, Department, Division, EmployeeNumber,'
            + ' MobilePhone, Phone, ManagerId, Manager.Name, IsActive, Profile.Name'
            + (dateFields.isEmpty() ? '' : ', ' + String.join(dateFields, ', '))
            + ' FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1';
        List<User> users = Database.query(soql);
        if (users.isEmpty()) {
            throw new AuraHandledException('User not found.');
        }
        User record = users[0];
        UserDetails details = new UserDetails();
        details.userId = record.Id;
        details.name = record.Name;
        details.firstName = record.FirstName;
        details.lastName = record.LastName;
        details.email = record.Email;
        details.username = record.Username;
        details.title = record.Title;
        details.department = record.Department;
        details.division = record.Division;
        details.employeeNumber = record.EmployeeNumber;
        details.mobilePhone = record.MobilePhone;
        details.phone = record.Phone;
        details.managerId = record.ManagerId;
        details.managerName = record.Manager?.Name;
        details.isActive = record.IsActive;
        details.profileName = record.Profile?.Name;
        details.dateFields = dateFields;
        if (dateFields.contains('Hire_Date__c')) {
            details.hireDate = (Date) record.get('Hire_Date__c');
        }
        if (dateFields.contains('Resignation_Date__c')) {
            details.resignationDate = (Date) record.get('Resignation_Date__c');
        }
        if (dateFields.contains('Last_Work_Day__c')) {
            details.lastWorkDay = (Date) record.get('Last_Work_Day__c');
        }

        details.seats = new List<Seat>();
        for (UserTerritory2Association link : [
            SELECT Territory2Id, Territory2.Name, Territory2.External_ID__c, Territory2.Territory_Type__c, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId
            WITH SYSTEM_MODE
            ORDER BY Territory2.Name
        ]) {
            Seat seat = new Seat();
            seat.territoryId = link.Territory2Id;
            seat.territoryName = link.Territory2.Name;
            seat.externalId = link.Territory2.External_ID__c;
            seat.territoryType = link.Territory2.Territory_Type__c;
            seat.role = link.RoleInTerritory2;
            details.seats.add(seat);
        }
        details.scheduled = SeatChangeService.getScheduledChanges(userId);
        details.history = SeatChangeService.getSeatHistory(userId);
        return details;
    }

    @AuraEnabled
    public static void saveUserDetails(String formJson) {
        SeatChangeService.requireManageUsers();
        UserForm form = String.isBlank(formJson) ? null : (UserForm) JSON.deserialize(formJson, UserForm.class);
        if (form == null || form.userId == null) {
            throw new AuraHandledException('User is required.');
        }
        if (String.isBlank(form.lastName)) {
            throw new AuraHandledException('Last name is required.');
        }
        if (String.isBlank(form.email)) {
            throw new AuraHandledException('Email is required.');
        }
        if (String.isBlank(form.username)) {
            throw new AuraHandledException('Username is required.');
        }
        if (form.managerId != null && form.managerId == form.userId) {
            throw new AuraHandledException('A person cannot be their own manager.');
        }

        User target = new User(Id = form.userId);
        target.FirstName = blankToNull(form.firstName);
        target.LastName = form.lastName.trim();
        target.Email = form.email.trim();
        target.Username = form.username.trim();
        target.Title = blankToNull(form.title);
        target.Department = blankToNull(form.department);
        target.Division = blankToNull(form.division);
        target.EmployeeNumber = blankToNull(form.employeeNumber);
        target.MobilePhone = blankToNull(form.mobilePhone);
        target.Phone = blankToNull(form.phone);
        target.ManagerId = form.managerId;
        List<String> dateFields = availableDateFields();
        Map<String, String> dateValues = new Map<String, String>{
            'Hire_Date__c' => form.hireDate,
            'Resignation_Date__c' => form.resignationDate,
            'Last_Work_Day__c' => form.lastWorkDay
        };
        for (String field : dateFields) {
            String raw = dateValues.get(field);
            target.put(field, String.isBlank(raw) ? null : Date.valueOf(raw.trim().left(10)));
        }

        try {
            update as system target;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }

    private static List<String> availableDateFields() {
        Map<String, Schema.SObjectField> userFields = User.SObjectType.getDescribe().fields.getMap();
        List<String> present = new List<String>();
        for (String api : OPTIONAL_DATES) {
            if (userFields.containsKey(api)) {
                present.add(api);
            }
        }
        return present;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
