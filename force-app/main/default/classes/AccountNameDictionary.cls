/**
 * Data-driven Arabic/English name variant library for Egypt / MENA field ops.
 * Canonical group maps to Latin spelling variants and Arabic forms.
 * Consumed by AccountCognitiveSearch for Accounts tab + New Account master search.
 * Add names here in one place; lookup is bidirectional after folding.
 */
public with sharing class AccountNameDictionary {
  public static List<List<String>> allGroups() {
    List<List<String>> all = new List<List<String>>();
    all.addAll(groupsPart1());
    all.addAll(groupsPart2());
    all.addAll(groupsPart3());
    all.addAll(groupsPart4());
    all.addAll(groupsPart5());
    all.addAll(groupsPart6());
    all.addAll(groupsPart7());
    all.addAll(brandGroups());
    return all;
  }

  public static Integer groupCount() {
    return allGroups().size();
  }

  private static List<List<String>> groupsPart1() {
    return new List<List<String>>{
      new List<String>{ 'Mohamed', 'Mohammed', 'Muhammad', 'Mohammad', 'Muhammed', 'Mohamad', 'محمد', 'محمّد' },
      new List<String>{ 'Ahmed', 'Ahmad', 'Ahmet', 'أحمد', 'احمد' },
      new List<String>{ 'Mahmoud', 'Mahmud', 'Mahmood', 'محمود' },
      new List<String>{ 'Ali', 'Aly', 'علي', 'على' },
      new List<String>{ 'Hassan', 'Hasan', 'حسن' },
      new List<String>{ 'Hussein', 'Hussain', 'Hossein', 'Husain', 'Hussien', 'حسين' },
      new List<String>{ 'Omar', 'Umar', 'عمر' },
      new List<String>{ 'Osman', 'Othman', 'Uthman', 'Usman', 'عثمان' },
      new List<String>{ 'Mostafa', 'Mustafa', 'Moustafa', 'مصطفى', 'مصطفي' },
      new List<String>{ 'Ibrahim', 'Ebrahim', 'Ibraheem', 'إبراهيم', 'ابراهيم' },
      new List<String>{ 'Youssef', 'Yusuf', 'Yousef', 'Yosef', 'Yousif', 'يوسف' },
      new List<String>{ 'Khaled', 'Khalid', 'خالد' },
      new List<String>{ 'Tarek', 'Tareq', 'Tariq', 'Tarik', 'طارق' },
      new List<String>{ 'Sherif', 'Sharif', 'Shareef', 'شريف' },
      new List<String>{ 'Karim', 'Kareem', 'كريم' },
      new List<String>{ 'Amr', 'Amro', 'Amrou', 'عمرو' },
      new List<String>{ 'Hany', 'Hani', 'هاني' },
      new List<String>{ 'Nader', 'Nadir', 'نادر' },
      new List<String>{ 'Samir', 'Sameer', 'سمير' },
      new List<String>{ 'Magdy', 'Magdi', 'Majdi', 'مجدي' },
      new List<String>{ 'Hossam', 'Hussam', 'Hosam', 'حسام' },
      new List<String>{ 'Wael', 'Wail', 'Wayel', 'وائل' },
      new List<String>{ 'Ramy', 'Rami', 'رامي' },
      new List<String>{ 'Tamer', 'Tamir', 'تامر' },
      new List<String>{ 'Ayman', 'Aiman', 'أيمن', 'ايمن' },
      new List<String>{ 'Ashraf', 'أشرف', 'اشرف' },
      new List<String>{ 'Sayed', 'Sayyed', 'Syed', 'Elsayed', 'El-Sayed', 'Alsayed', 'El Sayed', 'السيد', 'سيد' },
      new List<String>{ 'Maher', 'ماهر' },
      new List<String>{ 'Nabil', 'Nabeel', 'نبيل' },
      new List<String>{ 'Adel', 'Adil', 'عادل' },
      new List<String>{ 'Hatem', 'Hatim', 'حاتم' },
      new List<String>{ 'Essam', 'Issam', 'Esam', 'عصام' },
      new List<String>{ 'Emad', 'Imad', 'عماد' },
      new List<String>{ 'Ehab', 'Ihab', 'إيهاب', 'ايهاب' },
      new List<String>{ 'Gamal', 'Jamal', 'جمال' },
      new List<String>{ 'Yasser', 'Yasir', 'Yasar', 'ياسر' },
      new List<String>{ 'Waleed', 'Walid', 'وليد' },
      new List<String>{ 'Osama', 'Usama', 'Oussama', 'أسامة', 'اسامة' },
      new List<String>{ 'Salah', 'صلاح' },
      new List<String>{ 'Saleh', 'Salih', 'صالح' }
    };
  }
  private static List<List<String>> groupsPart2() {
    return new List<List<String>>{
      new List<String>{ 'Said', 'Saeed', 'Sayeed', 'Saied', 'سعيد' },
      new List<String>{ 'Hamdy', 'Hamdi', 'حمدي' },
      new List<String>{ 'Fathy', 'Fathi', 'فتحي' },
      new List<String>{ 'Reda', 'Rida', 'Redha', 'رضا' },
      new List<String>{ 'Sameh', 'سامح' },
      new List<String>{ 'Taha', 'طه' },
      new List<String>{ 'Anwar', 'أنور', 'انور' },
      new List<String>{ 'Farouk', 'Faruk', 'Farooq', 'Farouq', 'فاروق' },
      new List<String>{ 'Mansour', 'Mansur', 'منصور' },
      new List<String>{ 'Abbas', 'عباس' },
      new List<String>{ 'Lotfy', 'Lotfi', 'لطفي' },
      new List<String>{ 'Zaki', 'Zaky', 'زكي' },
      new List<String>{ 'Kamel', 'Kamil', 'Kameel', 'كامل' },
      new List<String>{ 'Faisal', 'Faysal', 'فيصل' },
      new List<String>{ 'Bassem', 'Basim', 'Bassim', 'باسم' },
      new List<String>{ 'Bassam', 'بسام' },
      new List<String>{ 'Nasser', 'Naser', 'Nasir', 'ناصر' },
      new List<String>{ 'Helmy', 'Helmi', 'حلمي' },
      new List<String>{ 'Shawky', 'Shawki', 'شوقي' },
      new List<String>{ 'Fawzy', 'Fawzi', 'فوزي' },
      new List<String>{ 'Galal', 'Jalal', 'جلال' },
      new List<String>{ 'Medhat', 'Midhat', 'مدحت' },
      new List<String>{ 'Maged', 'Majed', 'Magid', 'ماجد' },
      new List<String>{ 'Mourad', 'Murad', 'مراد' },
      new List<String>{ 'Raafat', 'Rafat', 'رأفت', 'رافت' },
      new List<String>{ 'Ezzat', 'Ezat', 'Izzat', 'عزت' },
      new List<String>{ 'Shady', 'Shadi', 'شادي' },
      new List<String>{ 'Hisham', 'Hesham', 'هشام' },
      new List<String>{ 'Hazem', 'Hazim', 'حازم' },
      new List<String>{ 'Hamza', 'Hamzah', 'حمزة', 'حمزه' },
      new List<String>{ 'Bilal', 'Bilel', 'بلال' },
      new List<String>{ 'Yasin', 'Yaseen', 'Yassin', 'Yassine', 'ياسين' },
      new List<String>{ 'Zakaria', 'Zakariya', 'Zakarya', 'زكريا' },
      new List<String>{ 'Sami', 'Sammy', 'سامي' },
      new List<String>{ 'Fouad', 'Fuad', 'فؤاد', 'فواد' },
      new List<String>{ 'Naguib', 'Najeeb', 'Najib', 'نجيب' },
      new List<String>{ 'Atef', 'Atif', 'عاطف' },
      new List<String>{ 'Awad', 'عوض' },
      new List<String>{ 'Bahaa', 'Baha', 'بهاء' },
      new List<String>{ 'Badr', 'بدر' }
    };
  }
  private static List<List<String>> groupsPart3() {
    return new List<List<String>>{
      new List<String>{ 'Dawoud', 'Dawood', 'Daoud', 'داود' },
      new List<String>{ 'Eid', 'عيد' },
      new List<String>{ 'Gaber', 'Jaber', 'جابر' },
      new List<String>{ 'Gamil', 'Jamil', 'جميل' },
      new List<String>{ 'Hafez', 'Hafiz', 'حافظ' },
      new List<String>{ 'Hamed', 'Hamid', 'حامد' },
      new List<String>{ 'Hamada', 'حمادة', 'حماده' },
      new List<String>{ 'Kamal', 'كمال' },
      new List<String>{ 'Khalifa', 'Khalifah', 'خليفة', 'خليفه' },
      new List<String>{ 'Mounir', 'Munir', 'Moneer', 'منير' },
      new List<String>{ 'Naeem', 'Naim', 'نعيم' },
      new List<String>{ 'Raed', 'Raid', 'رائد' },
      new List<String>{ 'Ramadan', 'Ramadhan', 'رمضان' },
      new List<String>{ 'Riad', 'Riyad', 'Riyadh', 'رياض' },
      new List<String>{ 'Safwat', 'صفوت' },
      new List<String>{ 'Salama', 'سلامة', 'سلامه' },
      new List<String>{ 'Salem', 'سالم' },
      new List<String>{ 'Salim', 'Seleem', 'Selim', 'سليم' },
      new List<String>{ 'Shaaban', 'Shaban', 'شعبان' },
      new List<String>{ 'Sobhy', 'Sobhi', 'Subhi', 'صبحي' },
      new List<String>{ 'Soliman', 'Suliman', 'Suleiman', 'Sulaiman', 'سليمان' },
      new List<String>{ 'Wahid', 'Waheed', 'وحيد' },
      new List<String>{ 'Yahia', 'Yahya', 'Yehia', 'يحيى', 'يحيي' },
      new List<String>{ 'Ziad', 'Zyad', 'Ziyad', 'زياد' },
      new List<String>{ 'Ismail', 'Ismael', 'Esmail', 'إسماعيل', 'اسماعيل' },
      new List<String>{ 'Mamdouh', 'Mamduh', 'ممدوح' },
      new List<String>{ 'Refaat', 'Refat', 'Rifaat', 'رفعت' },
      new List<String>{ 'Saber', 'Sabir', 'صابر' },
      new List<String>{ 'Saad', 'سعد' },
      new List<String>{ 'Tawfik', 'Tawfiq', 'Tewfik', 'توفيق' },
      new List<String>{ 'Metwally', 'Metwali', 'Metwaly', 'متولي' },
      new List<String>{ 'Hegazy', 'Hegazi', 'Higazy', 'حجازي' },
      new List<String>{ 'Roshdy', 'Roshdi', 'Rushdi', 'رشدي' },
      new List<String>{ 'Shawkat', 'شوكت' },
      new List<String>{ 'Mina', 'Meena', 'مينا' },
      new List<String>{ 'George', 'Girgis', 'Guirguis', 'Gerges', 'جورج', 'جرجس' },
      new List<String>{ 'Beshoy', 'Bishoy', 'Bishoi', 'بيشوي' },
      new List<String>{ 'Kirolos', 'Kyrillos', 'Cyril', 'كيرلس' },
      new List<String>{ 'Fadi', 'Fady', 'فادي' },
      new List<String>{ 'Mikhail', 'Michael', 'Michel', 'مايكل', 'ميخائيل' }
    };
  }
  private static List<List<String>> groupsPart4() {
    return new List<List<String>>{
      new List<String>{ 'Botros', 'Boutros', 'Peter', 'بطرس' },
      new List<String>{ 'Morcos', 'Markos', 'Mark', 'مرقس', 'مارك' },
      new List<String>{ 'Boulos', 'Boulus', 'Paul', 'بولس' },
      new List<String>{ 'Anton', 'Antoun', 'Anthony', 'أنطون', 'انطون' },
      new List<String>{ 'Haroun', 'Harun', 'Aaron', 'هارون' },
      new List<String>{ 'Younis', 'Yunis', 'Younes', 'يونس' },
      new List<String>{ 'Ishaq', 'Isaac', 'Ishak', 'إسحاق', 'اسحاق' },
      new List<String>{ 'Abdelrahman', 'Abdel Rahman', 'Abd El Rahman', 'Abd-El-Rahman', 'Abdulrahman', 'Abdul Rahman', 'Abd al-Rahman', 'Abdurrahman', 'AbdElRahman', 'عبدالرحمن', 'عبد الرحمن' },
      new List<String>{ 'Abdelaziz', 'Abdel Aziz', 'Abd El Aziz', 'Abdulaziz', 'Abdul Aziz', 'Abd al-Aziz', 'AbdElAziz', 'عبدالعزيز', 'عبد العزيز' },
      new List<String>{ 'Abdelhamid', 'Abdel Hamid', 'Abd El Hamid', 'Abdulhamid', 'Abdul Hamid', 'عبدالحميد', 'عبد الحميد' },
      new List<String>{ 'Abdelwahab', 'Abdel Wahab', 'Abd El Wahab', 'Abdulwahab', 'Abdul Wahab', 'عبدالوهاب', 'عبد الوهاب' },
      new List<String>{ 'Abdullah', 'Abdallah', 'Abd Allah', 'Abdulla', 'Abdellah', 'عبدالله', 'عبد الله' },
      new List<String>{ 'Abdelkader', 'Abdel Kader', 'Abd El Kader', 'Abdelqader', 'Abdulqadir', 'عبدالقادر', 'عبد القادر' },
      new List<String>{ 'Abdelghani', 'Abdel Ghani', 'Abd El Ghani', 'Abdelghany', 'عبدالغني', 'عبد الغني', 'عبدالغنى' },
      new List<String>{ 'Abdelhadi', 'Abdel Hadi', 'Abd El Hadi', 'عبدالهادي', 'عبد الهادي' },
      new List<String>{ 'Abdelkarim', 'Abdel Karim', 'Abd El Karim', 'Abdelkareem', 'عبدالكريم', 'عبد الكريم' },
      new List<String>{ 'Abdelfattah', 'Abdel Fattah', 'Abd El Fattah', 'Abdalfattah', 'عبدالفتاح', 'عبد الفتاح' },
      new List<String>{ 'Abdelnasser', 'Abdel Nasser', 'Abd El Nasser', 'Abdelnasir', 'عبدالناصر', 'عبد الناصر' },
      new List<String>{ 'Abdelhalim', 'Abdel Halim', 'Abd El Halim', 'Abdelhaleem', 'عبدالحليم', 'عبد الحليم' },
      new List<String>{ 'Abdelsalam', 'Abdel Salam', 'Abd El Salam', 'Abdelsalaam', 'عبدالسلام', 'عبد السلام' },
      new List<String>{ 'Abdelmoneim', 'Abdel Moneim', 'Abd El Moneim', 'Abdelmonem', 'Abdelmunim', 'عبدالمنعم', 'عبد المنعم' },
      new List<String>{ 'Abdellatif', 'Abdelatif', 'Abdel Latif', 'Abd El Latif', 'Abdullatif', 'عبداللطيف', 'عبد اللطيف' },
      new List<String>{ 'Abdelmageed', 'Abdelmeguid', 'Abdel Meguid', 'Abd El Mageed', 'عبدالمجيد', 'عبد المجيد' },
      new List<String>{ 'Abdelraouf', 'Abdel Raouf', 'Abd El Raouf', 'Abdelrauf', 'عبدالرؤوف', 'عبد الرؤوف' },
      new List<String>{ 'Abdelmoaty', 'Abdel Moaty', 'Abd El Moaty', 'Abdelmoty', 'عبدالمعطي', 'عبد المعطي' },
      new List<String>{ 'Abdelaal', 'Abdel Aal', 'Abd El Aal', 'Abdelal', 'عبدالعال', 'عبد العال' },
      new List<String>{ 'Abdeldayem', 'Abdel Dayem', 'Abd El Dayem', 'عبدالدايم', 'عبد الدايم' },
      new List<String>{ 'Fatma', 'Fatima', 'Fatimah', 'Fatema', 'فاطمة', 'فاطمه' },
      new List<String>{ 'Aisha', 'Aysha', 'Ayesha', 'Aicha', 'عائشة', 'عايشة', 'عائشه' },
      new List<String>{ 'Mona', 'Muna', 'منى', 'مني' },
      new List<String>{ 'Heba', 'Hiba', 'Hibah', 'هبة', 'هبه' },
      new List<String>{ 'Nour', 'Noor', 'Nur', 'نور' },
      new List<String>{ 'Noura', 'Nora', 'Noora', 'نورا', 'نوره', 'نورة' },
      new List<String>{ 'Sara', 'Sarah', 'Sarra', 'سارة', 'ساره' },
      new List<String>{ 'Mariam', 'Maryam', 'مريم' },
      new List<String>{ 'Dina', 'Deena', 'دينا' },
      new List<String>{ 'Yasmin', 'Yasmeen', 'Yasmine', 'Jasmin', 'ياسمين' },
      new List<String>{ 'Ghada', 'Ghadah', 'غادة', 'غاده' },
      new List<String>{ 'Hala', 'هالة', 'هاله' },
      new List<String>{ 'Iman', 'Eman', 'Imaan', 'إيمان', 'ايمان' },
      new List<String>{ 'Amina', 'Ameena', 'Aminah', 'أمينة', 'امينة' }
    };
  }
  private static List<List<String>> groupsPart5() {
    return new List<List<String>>{
      new List<String>{ 'Marwa', 'مروة', 'مروه' },
      new List<String>{ 'Hoda', 'Huda', 'Houda', 'هدى', 'هدي' },
      new List<String>{ 'Nada', 'ندى', 'ندي' },
      new List<String>{ 'Mai', 'May', 'Mae', 'مي' },
      new List<String>{ 'Aya', 'Ayah', 'Aia', 'آية', 'اية', 'آيه' },
      new List<String>{ 'Esraa', 'Israa', 'Isra', 'إسراء', 'اسراء' },
      new List<String>{ 'Rania', 'Ranya', 'رانيا' },
      new List<String>{ 'Rasha', 'رشا' },
      new List<String>{ 'Reem', 'Rim', 'ريم' },
      new List<String>{ 'Salma', 'سلمى', 'سلمي' },
      new List<String>{ 'Sahar', 'سحر' },
      new List<String>{ 'Samah', 'سماح' },
      new List<String>{ 'Shaimaa', 'Shaima', 'Shaymaa', 'شيماء' },
      new List<String>{ 'Doaa', 'Duaa', 'دعاء' },
      new List<String>{ 'Dalia', 'Dalya', 'داليا' },
      new List<String>{ 'Hanan', 'حنان' },
      new List<String>{ 'Inas', 'Enas', 'إيناس', 'ايناس' },
      new List<String>{ 'Karima', 'Kareema', 'كريمة', 'كريمه' },
      new List<String>{ 'Laila', 'Layla', 'Leila', 'ليلى', 'ليلي' },
      new List<String>{ 'Lamia', 'Lamiaa', 'لمياء' },
      new List<String>{ 'Maha', 'مها' },
      new List<String>{ 'Manal', 'منال' },
      new List<String>{ 'Mervat', 'Mirvat', 'ميرفت' },
      new List<String>{ 'Naglaa', 'Nagla', 'نجلاء' },
      new List<String>{ 'Nashwa', 'نشوى', 'نشوي' },
      new List<String>{ 'Ola', 'علا' },
      new List<String>{ 'Omnia', 'Omniya', 'أمنية', 'امنية' },
      new List<String>{ 'Randa', 'راندا' },
      new List<String>{ 'Sabah', 'صباح' },
      new List<String>{ 'Safa', 'Safaa', 'صفاء' },
      new List<String>{ 'Samia', 'سامية', 'ساميه' },
      new List<String>{ 'Siham', 'Seham', 'سهام' },
      new List<String>{ 'Soad', 'Souad', 'Suad', 'سعاد' },
      new List<String>{ 'Wafaa', 'Wafa', 'وفاء' },
      new List<String>{ 'Walaa', 'Wala', 'ولاء' },
      new List<String>{ 'Yara', 'يارا' },
      new List<String>{ 'Zeinab', 'Zainab', 'Zaynab', 'زينب' },
      new List<String>{ 'Amal', 'Amaal', 'أمل', 'امل' },
      new List<String>{ 'Asmaa', 'Asma', 'أسماء', 'اسماء' },
      new List<String>{ 'Farida', 'Fareeda', 'فريدة', 'فريده' }
    };
  }
  private static List<List<String>> groupsPart6() {
    return new List<List<String>>{
      new List<String>{ 'Faten', 'Fatin', 'فاتن' },
      new List<String>{ 'Gehan', 'Jihan', 'Gihan', 'جيهان' },
      new List<String>{ 'Ibtisam', 'Ebtisam', 'ابتسام' },
      new List<String>{ 'Magda', 'ماجدة', 'ماجده' },
      new List<String>{ 'Nermeen', 'Nermin', 'Nermine', 'نرمين' },
      new List<String>{ 'Nihal', 'نهال' },
      new List<String>{ 'Omaima', 'Umaima', 'أميمة', 'اميمة' },
      new List<String>{ 'Radwa', 'رضوى', 'رضوي' },
      new List<String>{ 'Rehab', 'رحاب' },
      new List<String>{ 'Sherine', 'Shereen', 'Shirin', 'شيرين' },
      new List<String>{ 'Somaya', 'Sumaya', 'سمية', 'سميه' },
      new List<String>{ 'Suzan', 'Susan', 'Suzanne', 'سوزان' },
      new List<String>{ 'Taghreed', 'Taghrid', 'تغريد' },
      new List<String>{ 'Noha', 'Nouha', 'Nuha', 'نهى', 'نهي' },
      new List<String>{ 'Youmna', 'Yomna', 'يمنى', 'يمني' },
      new List<String>{ 'Malak', 'ملاك' },
      new List<String>{ 'Habiba', 'Habeeba', 'حبيبة', 'حبيبه' },
      new List<String>{ 'Farah', 'فرح' },
      new List<String>{ 'Lina', 'Leena', 'لينا' },
      new List<String>{ 'Maya', 'مايا' },
      new List<String>{ 'Basmala', 'بسملة', 'بسمله' },
      new List<String>{ 'Howayda', 'Howaida', 'هويدا' },
      new List<String>{ 'Marina', 'مارينا' },
      new List<String>{ 'Demiana', 'Damiana', 'دميانة' },
      new List<String>{ 'Mary', 'Marie', 'ماري' },
      new List<String>{ 'Christine', 'Kristine', 'كريستين' },
      new List<String>{ 'Hadeer', 'Hadir', 'هدير' },
      new List<String>{ 'Menna', 'Mennah', 'منة', 'منه' },
      new List<String>{ 'Jannah', 'Janna', 'جنة', 'جنه' },
      new List<String>{ 'Elmasry', 'El-Masry', 'Almasry', 'El Masry', 'Masry', 'المصري' },
      new List<String>{ 'Elsharif', 'El-Sharif', 'Alsharif', 'El Sharif', 'الشريف' },
      new List<String>{ 'Elkhatib', 'El-Khatib', 'Alkhatib', 'El Khatib', 'الخطيب' },
      new List<String>{ 'Elshazly', 'El-Shazly', 'Alshazly', 'El Shazly', 'الشاذلي' },
      new List<String>{ 'Elgohary', 'El-Gohary', 'Algohary', 'El Gohary', 'الجوهري' },
      new List<String>{ 'Elnahas', 'El-Nahas', 'Alnahas', 'El Nahas', 'النحاس' },
      new List<String>{ 'Dessouky', 'Desouky', 'Dasouki', 'دسوقي' },
      new List<String>{ 'Bayoumi', 'Bayumi', 'Bayomy', 'بيومي' },
      new List<String>{ 'Darwish', 'Darwesh', 'درويش' },
      new List<String>{ 'Ghanem', 'Ghanim', 'غانم' },
      new List<String>{ 'Habib', 'Habeeb', 'حبيب' }
    };
  }
  private static List<List<String>> groupsPart7() {
    return new List<List<String>>{
      new List<String>{ 'Hakim', 'Hakeem', 'حكيم' },
      new List<String>{ 'Helal', 'Hilal', 'هلال' },
      new List<String>{ 'Nassar', 'نصار' },
      new List<String>{ 'Ashour', 'Ashur', 'عاشور' },
      new List<String>{ 'Bakr', 'Baker', 'بكر' },
      new List<String>{ 'Qasem', 'Qasim', 'Kassem', 'قاسم' },
      new List<String>{ 'Radi', 'Rady', 'راضي' }
    };
  }

  /** Pharmacy / HCO brands — on top of grapheme transliteration, not instead of it. */
  private static List<List<String>> brandGroups() {
    return new List<List<String>>{
      new List<String>{
        'El Ezaby',
        'Ezaby',
        'Elezaby',
        'El-Ezaby',
        'Ezzaby',
        'El Ezzaby',
        'ElEzaby',
        '\u0627\u0644\u0639\u0632\u0628\u064A',
        '\u0639\u0632\u0628\u064A'
      },
      new List<String>{
        'Seif',
        'El Seif',
        'Elseif',
        'Saif',
        '\u0627\u0644\u0633\u064A\u0641',
        '\u0633\u064A\u0641'
      },
      new List<String>{ '19011', '\u0661\u0669\u0660\u0661\u0661' },
      new List<String>{ 'Misr', 'El Misr', 'Masr', '\u0645\u0635\u0631' },
      new List<String>{ 'Gad', '\u062C\u0627\u062F' },
      new List<String>{
        'El Nabawy',
        'Nabawy',
        'Elnabawy',
        '\u0627\u0644\u0646\u0628\u0648\u064A',
        '\u0646\u0628\u0648\u064A'
      }
    };
  }
}