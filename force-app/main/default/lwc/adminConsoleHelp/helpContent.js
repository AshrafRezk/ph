/** Offline bilingual help corpus. English is source of truth; Arabic is a parallel walkthrough. */
export const HELP_ITEMS = [
    {
        id: 'field-app-manager',
        tile: 'Field App Manager',
        tileAr: 'مدير تطبيق الميدان',
        intents: ['home widgets', 'hide rings', 'class engine toggle', 'requests toggle', 'field ai', 'widgets', 'show hide'],
        phrase: 'When I want to show or hide Field home widgets, Class Engine, or request types for all reps, I open Field App Manager.',
        phraseAr: 'عندما أريد إظهار أو إخفاء ودجات الصفحة الرئيسية أو محرك التصنيف أو أنواع الطلبات لكل المندوبين، أفتح مدير تطبيق الميدان.',
        steps: [
            'Open Field App Manager from Admin Console.',
            'Toggle the home widgets and performance rings you need.',
            'Enable or disable Class Engine and Field AI.',
            'Turn Requests on and choose allowed request types.',
            'Save so Lightning and the offline app pick up the same flags.'
        ],
        stepsAr: [
            'افتح مدير تطبيق الميدان من وحدة الإدارة.',
            'فعّل أو أوقف ودجات الصفحة الرئيسية وحلقات الأداء.',
            'فعّل أو أوقف محرك التصنيف وذكاء الميدان.',
            'فعّل الطلبات واختر الأنواع المسموحة.',
            'احفظ ليظهر الإعداد في لايتنينج والتطبيق دون اتصال.'
        ]
    },
    {
        id: 'copilot-tabs',
        tile: 'Co-pilot app tabs',
        tileAr: 'تبويبات مساعد الطيار',
        intents: ['tabs', 'navigation', 'field tabs', 'lead tabs', 'force tabs', 'hide tab', 'app bar', 'pwa'],
        phrase: 'When I want to change which tabs appear in Field, Lead, Force, or Care Coach, I open Co-pilot app tabs.',
        phraseAr: 'عندما أريد تغيير التبويبات الظاهرة في الميدان أو القائد أو القوة أو كير كوتش، أفتح تبويبات مساعد الطيار.',
        steps: [
            'Open Co-pilot app tabs.',
            'Pick the app (Field, Lead, Force, or Care Coach).',
            'Turn tabs on or off for that app.',
            'Save, then confirm in the target app launcher.',
            'Check the field app after saving; changes apply to every rep.'
        ],
        stepsAr: [
            'افتح تبويبات مساعد الطيار.',
            'اختر التطبيق (ميدان / قائد / قوة / كير كوتش).',
            'فعّل أو أوقف التبويبات.',
            'احفظ ثم تحقق من شريط التطبيق.',
            'تحقق من تطبيق الميدان بعد الحفظ؛ التغيير يطبق على كل المندوبين.'
        ]
    },
    {
        id: 'visit-tabs',
        tile: 'Visit Tabs',
        tileAr: 'تبويبات الزيارة',
        intents: ['visit sections', 'call report tabs', 'orders on visit', 'pharmacy visit'],
        phrase: 'When I want each account record type to show different call-report sections, I open Visit Tabs.',
        phraseAr: 'عندما أريد أن يظهر لكل نوع حساب أقسام مختلفة في تقرير المكالمة، أفتح تبويبات الزيارة.',
        steps: [
            'Open Visit Tabs.',
            'Select Doctor, Pharmacy, or Institution.',
            'Enable the sections that type needs (Products, Samples, Orders, Requests, Store check).',
            'Save the layout.',
            'Open a matching visit and confirm the sections.'
        ],
        stepsAr: [
            'افتح تبويبات الزيارة.',
            'اختر طبيب أو صيدلية أو مؤسسة.',
            'فعّل الأقسام المطلوبة.',
            'احفظ التخطيط.',
            'افتح زيارة مطابقة وتأكد من الأقسام.'
        ]
    },
    {
        id: 'clm',
        tile: 'CLM',
        tileAr: 'إدارة العروض',
        intents: ['presentation', 'deck', 'slides', 'clm', 'html pdf'],
        phrase: 'When I want to upload or target a presentation deck to territories, I open CLM.',
        phraseAr: 'عندما أريد رفع عرض أو توجيهه لأقاليم، أفتح إدارة العروض.',
        steps: [
            'Open CLM.',
            'Create or select a presentation.',
            'Upload HTML or PDF slides.',
            'Set territory targeting.',
            'Confirm a rep in that territory can see the deck.'
        ],
        stepsAr: [
            'افتح إدارة العروض.',
            'أنشئ أو اختر عرضاً.',
            'ارفع شرائح HTML أو PDF.',
            'حدد الأقاليم المستهدفة.',
            'تأكد أن المندوب في الإقليم يرى العرض.'
        ]
    },
    {
        id: 'rating-layouts',
        tile: 'Rating Layouts',
        tileAr: 'تخطيطات التقييم',
        intents: ['rating form', 'classification questions', 'atr'],
        phrase: 'When I want the field rating form questions to match SFE design, I open Rating Layouts.',
        phraseAr: 'عندما أريد أن تطابق أسئلة نموذج التقييم تصميم SFE، أفتح تخطيطات التقييم.',
        steps: [
            'Open Rating Layouts.',
            'Choose account, territory, or product layout.',
            'Edit questions in the live preview.',
            'Save.',
            'Open an account Ratings tab to verify.'
        ],
        stepsAr: [
            'افتح تخطيطات التقييم.',
            'اختر تخطيط الحساب أو الإقليم أو المنتج.',
            'عدّل الأسئلة مع المعاينة الحية.',
            'احفظ.',
            'افتح تبويب التقييمات على حساب للتحقق.'
        ]
    },
    {
        id: 'coaching-management',
        tile: 'Coaching Management',
        tileAr: 'إدارة التدريب الميداني',
        intents: ['coaching template', 'coach form'],
        phrase: 'When I want managers to use a specific coaching template, I open Coaching Management.',
        phraseAr: 'عندما أريد أن يستخدم المدراء قالب تدريب محدد، أفتح إدارة التدريب الميداني.',
        steps: [
            'Open Coaching Management.',
            'Browse or create a template.',
            'Design the sections managers fill.',
            'Activate the template.',
            'Open Create Coaching Event from a visit to confirm.'
        ],
        stepsAr: [
            'افتح إدارة التدريب الميداني.',
            'استعرض أو أنشئ قالباً.',
            'صمم أقسام المدراء.',
            'فعّل القالب.',
            'افتح إنشاء حدث تدريب من زيارة للتأكيد.'
        ]
    },
    {
        id: 'territory-management',
        tile: 'Territory Management',
        tileAr: 'إدارة الأقاليم',
        intents: ['territory', 'assign user', 'product line', 'hierarchy'],
        phrase: 'When I want to assign a user to a territory or fix the hierarchy, I open Territory Management.',
        phraseAr: 'عندما أريد تعيين مستخدم لإقليم أو إصلاح الهيكل، أفتح إدارة الأقاليم.',
        steps: [
            'Open Territory Management.',
            'Select the product line and territory.',
            'Review the assigned user and parent.',
            'Edit the assignment, then confirm the rep appears under the right manager in My Team.',
            'Confirm My Team matches the tree.'
        ],
        stepsAr: [
            'افتح إدارة الأقاليم.',
            'اختر خط المنتج والإقليم.',
            'راجع المستخدم المعيّن والأب.',
            'عدّل التعيين ثم تأكد أن المندوب يظهر تحت المدير الصحيح.',
            'تأكد أن فريقي يطابق الشجرة.'
        ]
    },
    {
        id: 'sfe-approvers',
        tile: 'SFE Approvers',
        tileAr: 'معتمدو SFE',
        intents: ['sfe approver', 'class engine approval', 'account approval', 'pending sfe', 'who approves'],
        phrase: 'When I want to change which SFE approves Class Engine cycles or new accounts for a line, I open SFE Approvers.',
        phraseAr: 'عندما أريد تغيير مسؤول SFE الذي يعتمد دورات Class Engine أو الحسابات الجديدة لخط معيّن، أفتح معتمدو SFE.',
        steps: [
            'Open SFE Approvers.',
            'Add the SFE if they are not listed yet.',
            'Tick their business units, or All lines.',
            'Choose Class Engine, New accounts, or both.',
            'Save changes and open a pending cycle or account to confirm.'
        ],
        stepsAr: [
            'افتح معتمدو SFE.',
            'أضف مسؤول SFE إن لم يكن موجوداً.',
            'حدد وحدات الأعمال الخاصة به، أو كل الخطوط.',
            'اختر Class Engine أو الحسابات الجديدة أو كليهما.',
            'احفظ التغييرات وافتح دورة أو حساباً معلقاً للتأكيد.'
        ]
    },
    {
        id: 'bricks-management',
        tile: 'Bricks Manager',
        tileAr: 'مدير الطوب الجغرافي',
        intents: [
            'brick',
            'bricks manager',
            '148',
            '702',
            'brick map',
            'draw brick',
            'brick region',
            'iqvia',
            'pharmacy membership'
        ],
        phrase: 'When I want to draw or rename 148 and 702 brick regions, or put sales in the brick of a pharmacy location, I open Bricks Manager.',
        phraseAr: 'عندما أريد رسم أو تسمية مناطق الطوب 148 و702، أو وضع المبيعات في طوبة موقع الصيدلية، أفتح مدير الطوب الجغرافي.',
        steps: [
            'Open Bricks Manager from Admin Console.',
            'Switch between 702 micro bricks and 148 bricks.',
            'Generate IMS outlines from OpenStreetMap, or Suggest from OSM on one brick.',
            'Edit the parcel on the map like HAP, then save. It lives on the brick record as GeoJSON.',
            'Apply regions to sales so distributor clients sit in the brick that holds their location.'
        ],
        stepsAr: [
            'افتح مدير الطوب الجغرافي من وحدة الإدارة.',
            'بدّل بين طوب 702 وطوب 148.',
            'ولّد مناطق IMS من OpenStreetMap أو اقترح واحدة ثم عدّلها على الخريطة.',
            'احفظ الاسم والرمز والأب والمدينة من اللوحة الجانبية.',
            'طبّق المناطق على المبيعات ليوضع عميل الموزع في الطوبة التي تضم موقعه.'
        ]
    },
    {
        id: 'products-manager',
        tile: 'Products Manager',
        tileAr: 'مدير المنتجات',
        intents: ['product alignment', 'brand territory', 'catalog', 'new product', 'add product', 'edit product', 'product price', 'new brand', 'new sample', 'deactivate product'],
        phrase: 'When I want to add a product, change its details, or align it to territories, I open Products Manager.',
        phraseAr: 'عندما أريد إضافة منتج أو تعديل بياناته أو محاذاته للأقاليم، أفتح مدير المنتجات.',
        steps: [
            'Open Products Manager.',
            'Click New product, or select a product and click Edit product.',
            'Choose the type and the brand or detail it belongs to, then fill code, line, strength, form and price.',
            'Click Save product. The code cannot change after saving.',
            'Tick the territories on the right and click Save Alignment.'
        ],
        stepsAr: [
            'افتح مدير المنتجات.',
            'اضغط منتج جديد، أو اختر منتجًا واضغط تعديل المنتج.',
            'اختر النوع والعلامة أو التفصيل الذي يتبعه، ثم أدخل الكود والخط والتركيز والشكل والسعر.',
            'اضغط حفظ المنتج. لا يمكن تغيير الكود بعد الحفظ.',
            'حدد الأقاليم على اليمين واضغط حفظ المحاذاة.'
        ]
    },
    {
        id: 'sample-logistics',
        tile: 'Sample Logistics',
        tileAr: 'لوجستيات العينات',
        intents: ['sample', 'lot', 'expiry', 'allocate', 'transfer'],
        phrase: 'When I want to allocate sample lots or review expiry, I open Sample Logistics.',
        phraseAr: 'عندما أريد تخصيص دفعات عينات أو مراجعة الصلاحية، أفتح لوجستيات العينات.',
        steps: [
            'Open Sample Logistics.',
            'Open request, allocate, transfer, or return.',
            'Read lot and expiry before dispense talk.',
            'Allocate lots by expiry, earliest first.',
            'Cancel a request only when Supply Chain has confirmed it will not be filled.'
        ],
        stepsAr: [
            'افتح لوجستيات العينات.',
            'افتح طلب أو تخصيص أو تحويل أو إرجاع.',
            'اقرأ الدفعة والصلاحية.',
            'خصص الدفعات حسب الصلاحية، الأقرب انتهاءً أولاً.',
            'ألغِ الطلب فقط بعد تأكيد سلسلة الإمداد أنه لن يُنفَّذ.'
        ]
    },
    {
        id: 'plan-manager',
        tile: 'Plan Manager',
        tileAr: 'مدير الخطط',
        intents: ['plan cycle', 'copy plan', 'coverage month'],
        phrase: 'When I want to review monthly plan cycles or copy a plan to the next month, I open Plan Manager.',
        phraseAr: 'عندما أريد مراجعة دورات الخطة الشهرية أو نسخ خطة إلى الشهر التالي، أفتح مدير الخطط.',
        steps: [
            'Open Plan Manager.',
            'Select the current cycle.',
            'Review covered people and dates.',
            'Copy overwrites targets in the destination month; check that month is empty or meant to be replaced.',
            'Do not overwrite a live production cycle.'
        ],
        stepsAr: [
            'افتح مدير الخطط.',
            'اختر الدورة الحالية.',
            'راجع الأشخاص والتواريخ.',
            'النسخ يستبدل الأهداف في الشهر الهدف؛ تأكد أنه فارغ أو مقصود استبداله.',
            'لا تنسخ فوق شهر يعمل عليه المندوبون حالياً.'
        ]
    },
    {
        id: 'call-target-rules',
        tile: 'Call Target Rules',
        tileAr: 'قواعد هدف المكالمات',
        intents: ['call rate', 'time off target', 'reduce calls'],
        phrase: 'When I want call targets to drop after time off or meetings, I open Call Target Rules.',
        phraseAr: 'عندما أريد أن تنخفض أهداف المكالمات بعد الإجازة أو الاجتماعات، أفتح قواعد هدف المكالمات.',
        steps: [
            'Open Call Target Rules.',
            'Choose which time-off types count, and the number of days before targets are pro-rated.',
            'Set the lowest target and the long-leave days.',
            'Save.',
            'Check a planner week with leave to confirm.'
        ],
        stepsAr: [
            'افتح قواعد هدف المكالمات.',
            'راجع قواعد التخفيض.',
            'اختر أنواع الإجازات المحتسبة وعدد الأيام قبل التخفيض، وأقل هدف وأيام الإجازة الطويلة.',
            'احفظ.',
            'تحقق من أسبوع مخطط فيه إجازة.'
        ]
    },
    {
        id: 'learning-module-management',
        tile: 'Learning Module Management',
        tileAr: 'إدارة وحدات التعلم',
        intents: ['learning', 'course', 'assignment', 'lms'],
        phrase: 'When I want to create a course or assign learning material, I open Learning Module Management.',
        phraseAr: 'عندما أريد إنشاء دورة أو تعيين مادة تعليمية، أفتح إدارة وحدات التعلم.',
        steps: [
            'Open Learning Module Management.',
            'Search existing materials or create one.',
            'Add a file or a link.',
            'Assign it to the people who should take it.',
            'Confirm the assignment shows for that user.'
        ],
        stepsAr: [
            'افتح إدارة وحدات التعلم.',
            'ابحث عن مادة أو أنشئ واحدة.',
            'أضف ملفاً أو رابطاً.',
            'عيّنها للأشخاص المطلوب تدريبهم.',
            'تأكد أن التعيين يظهر لذلك المستخدم.'
        ]
    },
    {
        id: 'quiz-management',
        tile: 'Quiz Management',
        tileAr: 'إدارة الاختبارات',
        intents: ['quiz', 'question bank', 'exam'],
        phrase: 'When I want to build a quiz or edit its questions, I open Quiz Management.',
        phraseAr: 'عندما أريد بناء اختبار أو تعديل أسئلته، أفتح إدارة الاختبارات.',
        steps: [
            'Open Quiz Management.',
            'Search for a quiz or create one.',
            'Add or edit questions.',
            'Save and set the quiz active when it is ready.',
            'Assign it from Learning Module Management when people should take it.'
        ],
        stepsAr: [
            'افتح إدارة الاختبارات.',
            'ابحث عن اختبار أو أنشئ واحداً.',
            'أضف أو عدّل الأسئلة.',
            'احفظ وفعّل الاختبار عندما يجهز.',
            'عيّنه من إدارة وحدات التعلم عندما يجب أن يؤديه الناس.'
        ]
    },
    {
        id: 'sales-policy',
        tile: 'Sales Policy',
        tileAr: 'سياسة المبيعات',
        intents: ['ceiling', 'share split', 'tender', 'public price', 'colest'],
        phrase: 'When I want the distribution ceiling, share split, or tender rules, I open Sales Policy.',
        phraseAr: 'عندما أريد سقف التوزيع أو تقسيم الحصة أو قواعد المناقصات، أفتح سياسة المبيعات.',
        steps: [
            'Open Sales Policy.',
            'Review the ceiling, share split, and tender exclusion.',
            'Check public-price math and the Colest exception.',
            'Save.',
            'Use a known month in Export month to confirm the numbers you expect.'
        ],
        stepsAr: [
            'افتح سياسة المبيعات.',
            'راجع السقف وتقسيم الحصة واستثناء المناقصات.',
            'راجع حساب سعر الجمهور واستثناء كولست.',
            'احفظ.',
            'استخدم شهراً معروفاً في تصدير الشهر للتأكد من الأرقام.'
        ]
    },
    {
        id: 'monthly-data-pack',
        tile: 'Monthly data pack',
        tileAr: 'حزمة بيانات الشهر',
        intents: ['zip', 'epda', 'pos', 'ibnsina', 'leave import', 'historical visits'],
        phrase: 'When I want to load a month of sales, leave, time off, and historical visits, I open Monthly data pack.',
        phraseAr: 'عندما أريد تحميل مبيعات شهر وإجازات ووقت خارج الإقليم وزيارات تاريخية، أفتح حزمة بيانات الشهر.',
        steps: [
            'Open Monthly data pack.',
            'Drop the month zip, or choose the spreadsheets.',
            'Wait for each file to be recognised and previewed.',
            'Import only after the preview looks right.',
            'Download the error CSV if a batch reports rows that did not load.'
        ],
        stepsAr: [
            'افتح حزمة بيانات الشهر.',
            'أسقط ملف الشهر المضغوط أو اختر الجداول.',
            'انتظر التعرف على كل ملف ومعاينته.',
            'استورد فقط بعد أن تبدو المعاينة صحيحة.',
            'نزّل ملف الأخطاء إذا أبلغ دفعة عن صفوف لم تُحمّل.'
        ]
    },
    {
        id: 'sales-export-month',
        tile: 'Export month',
        tileAr: 'تصدير الشهر',
        intents: ['export sales', 'download pharmacy sales', 'pharmacy sales data', 'sell-out', 'consolidated month', 'excel revenue'],
        phrase: 'When I want to download pharmacy sales (one month, all distributors) with product and revenue, I open Export month.',
        phraseAr: 'عندما أريد مبيعات الموزعين لشهر واحد مع المنتج والإيراد، أفتح تصدير الشهر.',
        steps: [
            'Open Export month.',
            'Pick any day in the report month.',
            'Choose a distributor, or leave all.',
            'Download the Excel file.',
            'Confirm product, quantity, and revenue are on each line.',
            'Read the 702 brick, 148 brick, Line, Territory and Rep columns to see where each sale landed.'
        ],
        stepsAr: [
            'افتح تصدير الشهر.',
            'اختر أي يوم في شهر التقرير.',
            'اختر موزعاً أو اترك الكل.',
            'نزّل ملف إكسل.',
            'تأكد أن المنتج والكمية والإيراد على كل سطر.',
            'راجع أعمدة البريك 702 و148 والخط والمنطقة والمندوب لترى أين احتُسب كل بيع.'
        ]
    },
    {
        id: 'target-governance',
        tile: 'Target Governance',
        tileAr: 'حوكمة الأهداف',
        intents: ['frequency alarm', 'list churn', 'out of target', 'deviation'],
        phrase: 'When I want frequency or list-change alarms, or the end-of-month out-of-target queue, I open Target Governance.',
        phraseAr: 'عندما أريد تنبيهات التكرار أو تغيير القائمة أو طابور نهاية الشهر خارج الهدف، أفتح حوكمة الأهداف.',
        steps: [
            'Open Target Governance.',
            'Set the frequency and list-change deviation percents.',
            'Save the alarm rule.',
            'Open the out-of-target queue for the month you are reviewing.',
            'Work proposals in the DM, then FI, then business-unit order.'
        ],
        stepsAr: [
            'افتح حوكمة الأهداف.',
            'اضبط نسب انحراف التكرار وتغيير القائمة.',
            'احفظ قاعدة التنبيه.',
            'افتح طابور خارج الهدف للشهر الذي تراجعه.',
            'عالج المقترحات بترتيب مدير المنطقة ثم المفتش ثم وحدة الأعمال.'
        ]
    },
    {
        id: 'service-request-types',
        tile: 'Service Request Types',
        tileAr: 'أنواع طلبات الخدمة',
        intents: ['request type', 'subtype', 'who can create', 'sample request type'],
        phrase: 'When I want to decide which request types exist and who can create them, I open Service Request Types.',
        phraseAr: 'عندما أريد تحديد أنواع الطلبات ومن يمكنه إنشاءها، أفتح أنواع طلبات الخدمة.',
        steps: [
            'Open Service Request Types.',
            'Add or edit a type, category, and subtype.',
            'Choose the job titles allowed to create it.',
            'Save.',
            'Confirm the type appears for that title in the field app.'
        ],
        stepsAr: [
            'افتح أنواع طلبات الخدمة.',
            'أضف أو عدّل النوع والفئة والنوع الفرعي.',
            'اختر المسميات المسموح لها بالإنشاء.',
            'احفظ.',
            'تأكد أن النوع يظهر لتلك المسميات في تطبيق الميدان.'
        ]
    },
    {
        id: 'distributors-management',
        tile: 'Distributors Management',
        tileAr: 'إدارة الموزعين',
        intents: ['distributor excel', 'pharmacy match', 'osm'],
        phrase: 'When I want to import distributor Excel and confirm pharmacy matches, I open Distributors Management.',
        phraseAr: 'عندما أريد استيراد إكسل الموزع وتأكيد مطابقة الصيدليات، أفتح إدارة الموزعين.',
        steps: [
            'Open Distributors Management.',
            'Import a native distributor file or review empty-state instructions.',
            'Open one pharmacy match.',
            'Confirm the match vs suggestion.',
            'Confirm a suggested match only after checking the pharmacy name and address.'
        ],
        stepsAr: [
            'افتح إدارة الموزعين.',
            'استورد ملف الموزع أو راجع التعليمات.',
            'افتح مطابقة صيدلية.',
            'أكد المطابقة مقابل الاقتراح.',
            'أكد الاقتراح فقط بعد مراجعة اسم الصيدلية وعنوانها.'
        ]
    },
    {
        id: 'target-master-lists',
        tile: 'Target & Master Lists',
        tileAr: 'قوائم الهدف والمستر',
        intents: ['target list', 'master list', 'final master', 'import organizations', 'call plan import'],
        phrase: 'When I want to import or export Organizations Final Master List or Target List (All Team), I open Target & Master Lists — upsert only, no wipe.',
        phraseAr: 'عندما أريد استيراد أو تصدير قائمة المنظمات أو قائمة الهدف، أفتح قوائم الهدف والمستر — تحديث فقط دون مسح.',
        steps: [
            'Open Target & Master Lists.',
            'Choose Organizations_FinalMaster_List or Target List (All Team).',
            'Import (upsert). Vacant employee codes (vac-*) are skipped.',
            'Or Export to download the current org sheet shape.',
            'Use Account Management Wipe & Load only for a full reset.'
        ],
        stepsAr: [
            'افتح قوائم الهدف والمستر.',
            'اختر ملف المستر أو قائمة الهدف.',
            'استورد (تحديث). أكواد الموظفين الشاغرة تُتخطى.',
            'أو صدّر الشكل الحالي من المؤسسة.',
            'استخدم مسح وتحميل في إدارة الحسابات فقط لإعادة تعيين كاملة.'
        ]
    },
    {
        id: 'account-management',
        tile: 'Account Management',
        tileAr: 'إدارة الحسابات',
        intents: ['duplicate', 'export accounts', 'wipe', 'master data'],
        phrase: 'When I want to review name/location duplicates or export accounts, I open Account Management — never wipe master data in a pass.',
        phraseAr: 'عندما أريد مراجعة التكرارات أو تصدير الحسابات، أفتح إدارة الحسابات — ولا تمسح البيانات الأساسية أثناء الاختبار.',
        steps: [
            'Open Account Management.',
            'Open the duplicate view.',
            'Export if needed.',
            'Do not wipe or destructive-load master data.',
            'Wipe & Load replaces every account and affiliation; use it only for a planned full reset.'
        ],
        stepsAr: [
            'افتح إدارة الحسابات.',
            'افتح عرض التكرار.',
            'صدّر إن لزم.',
            'استخدم الاستيراد والتعديل للتغييرات، وصدّر نسخة احتياطية أولاً.',
            'المسح والتحميل يستبدل كل الحسابات والانتماءات؛ استخدمه فقط لإعادة تعيين كاملة مخطط لها.'
        ]
    },
    {
        id: 'account-data-quality',
        tile: 'Account data quality',
        tileAr: 'جودة بيانات الحسابات',
        intents: [
            'cognitive duplicate',
            'nurture',
            'google places',
            'vezeeta',
            'greenlight',
            'data quality',
            'fill missing'
        ],
        phrase: 'When I want to scan existing accounts for cognitive duplicates or nurture missing Places/Vezeeta data with SFE greenlight, I open Account data quality.',
        phraseAr: 'عندما أريد فحص الحسابات الحالية للتكرار المعرفي أو إثراء البيانات الناقصة من أماكن جوجل وفيزيتا بموافقة التميز، أفتح جودة بيانات الحسابات.',
        steps: [
            'Open Account data quality.',
            'Choose record types, then run a duplicate or nurture scan.',
            'Review the proposal list when the batch is ready.',
            'Select all or some rows; for duplicates choose Mark or Merge, for nurture accept fields.',
            'Greenlight selected rows or dismiss the rest.'
        ],
        stepsAr: [
            'افتح جودة بيانات الحسابات.',
            'اختر أنواع السجلات ثم شغّل فحص التكرار أو الإثراء.',
            'راجع قائمة المقترحات عند اكتمال المهمة.',
            'حدد الكل أو بعض الصفوف؛ للتكرار اختر تعليم أو دمج، وللإثراء اقبل الحقول.',
            'وافق على المحدد أو تجاهل الباقي.'
        ]
    },
    {
        id: 'promo-grid',
        tile: 'Promo Grid Management',
        tileAr: 'إدارة شبكة الترويج',
        intents: ['promo weights', 'class targeting', '100 percent', 'promo grid import', 'promo grid export'],
        phrase: 'When I want line product weights and class targeting for Class Engine, I open Promo Grid Management.',
        phraseAr: 'عندما أريد أوزان منتجات الخط واستهداف الفئات لمحرك التصنيف، أفتح إدارة شبكة الترويج.',
        steps: [
            'Open Promo Grid Management.',
            'Select a line and edit weights, specialty focus, or class targeting so each section totals 100%.',
            'Download template for a blank workbook, or Export for current values (Products, Specialties, Classes sheets).',
            'Import the filled workbook, review the preview, then Apply — only sections with percentages replace existing rows.',
            'Save when product weights total 100%, then run Class Engine for the line.'
        ],
        stepsAr: [
            'افتح إدارة شبكة الترويج.',
            'اختر خطاً وعدّل الأوزان أو التخصصات أو الفئات لتجمع كل منها 100٪.',
            'نزّل القالب لملف فارغ أو صدّر القيم الحالية (أوراق المنتجات والتخصصات والفئات).',
            'استورد الملف المعبأ، راجع المعاينة، ثم طبّق — تُستبدل فقط الأقسام التي فيها نسب.',
            'احفظ عندما تجمع الأوزان 100٪، ثم شغّل محرك التصنيف للخط.'
        ]
    },
    {
        id: 'meetings-setup',
        tile: 'Meetings Setup',
        tileAr: 'إعداد الاجتماعات',
        intents: ['meeting type', 'approvers', 'who can create', 'meeting tabs', 'invitations'],
        phrase: 'When I want meeting types, who can create them, which tabs show, and approvers, I open Meetings Setup.',
        phraseAr: 'عندما أريد أنواع الاجتماعات ومن ينشئها وأي تبويبات تظهر والموافقين، أفتح إعداد الاجتماعات.',
        steps: [
            'Open Meetings Setup.',
            'Edit a meeting type (tabs, creators, departments, territories).',
            'Configure the approval chain for the department or type.',
            'Preview the chain for a sample user and amount.',
            'Confirm Meetings stay off the field phone launcher.'
        ],
        stepsAr: [
            'افتح إعداد الاجتماعات.',
            'عدّل نوع اجتماع (تبويبات، منشئون، أقسام، أقاليم).',
            'اضبط سلسلة الموافقة للقسم أو النوع.',
            'عاين السلسلة لمستخدم ومبلغ تجريبي.',
            'تأكد أن الاجتماعات لا تظهر في هاتف المندوب.'
        ]
    },
    {
        id: 'public-holidays',
        tile: 'Public Holidays',
        tileAr: 'العطلات الرسمية',
        intents: ['holiday', 'closed day', 'planner block'],
        phrase: 'When I want a company holiday to block the planner, I open Public Holidays.',
        phraseAr: 'عندما أريد أن تمنع عطلة رسمية التخطيط، أفتح العطلات الرسمية.',
        steps: [
            'Open Public Holidays.',
            'Find or add the holiday date.',
            'Save.',
            'Open a rep planner on that date.',
            'Confirm the day is closed for planning.'
        ],
        stepsAr: [
            'افتح العطلات الرسمية.',
            'ابحث أو أضف تاريخ العطلة.',
            'احفظ.',
            'افتح مخطط مندوب في ذلك التاريخ.',
            'تأكد أن اليوم مغلق للتخطيط.'
        ]
    },
    {
        id: 'planner-rules',
        tile: 'Planner Rules',
        tileAr: 'قواعد المخطط',
        intents: [
            'weekend',
            'overlap',
            'tot visit',
            'time off overlap',
            'holiday overlap',
            'allow warn block',
            'working days'
        ],
        phrase: 'When I want weekends or overlap Allow/Warn/Block for TOT, visits, meetings, and holidays, I open Planner Rules.',
        phraseAr: 'عندما أريد أيام العمل أو سياسة التداخل (سماح/تحذير/منع) للإجازة والزيارات والاجتماعات والعطلات، أفتح قواعد المخطط.',
        steps: [
            'Open Planner Rules.',
            'Tick the working days (Egypt default Sat–Wed).',
            'Set each overlap to Allow, Warn, or Block.',
            'Save.',
            'On the planner, try a conflicting visit or weekend slot and confirm the policy.'
        ],
        stepsAr: [
            'افتح قواعد المخطط.',
            'حدّد أيام العمل (الافتراضي سبت–أربعاء).',
            'اضبط كل تداخل على سماح أو تحذير أو منع.',
            'احفظ.',
            'في المخطط جرّب زيارة متعارضة أو يوم عطلة وتأكد من السياسة.'
        ]
    },
    {
        id: 'integrations-management',
        tile: 'Integrations Management',
        tileAr: 'إدارة التكاملات',
        intents: ['ims', 'onekey', 'maps', 'mendix', 'connector'],
        phrase: 'When I want connector status for IMS, OneKey, Maps, or Mendix, I open Integrations Management.',
        phraseAr: 'عندما أريد حالة موصلات IMS أو OneKey أو Maps أو Mendix، أفتح إدارة التكاملات.',
        steps: [
            'Open Integrations Management.',
            'Read each connector status.',
            'Open a linked admin module if offered.',
            'Change connector credentials only with IT.',
            'Not connected means the integration is not set up yet; it is not an error.'
        ],
        stepsAr: [
            'افتح إدارة التكاملات.',
            'اقرأ حالة كل موصل.',
            'افتح وحدة إدارة مرتبطة إن وُجدت.',
            'غيّر بيانات اعتماد الموصلات بالتنسيق مع تقنية المعلومات فقط.',
            'سجّل حالة غير متصل كمعلومة لا كفشل.'
        ]
    },
    {
        id: 'kpi-targets',
        tile: 'KPI Targets',
        tileAr: 'أهداف مؤشرات الأداء',
        intents: ['kpi target', 'coverage target', 'right frequency target', 'quiz target', 'scorecard'],
        phrase: 'When I want to adjust role KPI targets that Field and Lead scorecards use, I open KPI Targets.',
        phraseAr: 'عندما أريد تعديل أهداف مؤشرات الأداء حسب الدور المستخدمة في لوحات الميدان والقائد، أفتح أهداف مؤشرات الأداء.',
        steps: [
            'Open KPI Targets.',
            'Select a role (MSR, DSM, ASM, NSM, BM).',
            'Edit the percentage targets.',
            'Save.',
            'Refresh Field or Lead KPIs and confirm the new targets.'
        ],
        stepsAr: [
            'افتح أهداف مؤشرات الأداء.',
            'اختر دوراً.',
            'عدّل نسب الأهداف.',
            'احفظ.',
            'حدّث مؤشرات الميدان أو القائد وتأكد.'
        ]
    },
    {
        id: 'chrome-data-tools',
        tile: 'Chrome and Data Tools',
        tileAr: 'إضافات كروم وأدوات البيانات',
        intents: ['salesforce inspector', 'soql', 'dml', 'upsert', 'user territory', 'query'],
        phrase: 'When I want Chrome extensions or safe SOQL/DML recipes for accounts and territories, I open Chrome and Data Tools.',
        phraseAr: 'عندما أريد إضافات كروم أو وصفات SOQL/DML آمنة للحسابات والأقاليم، أفتح إضافات كروم وأدوات البيانات.',
        steps: [
            'Open Chrome and Data Tools.',
            'Install recommended extensions from the Chrome Web Store links.',
            'Copy a SOQL recipe for the object you need.',
            'Read the DML explanation before insert/update/upsert/delete.',
            'Use these tools to read and check data; run bulk changes in a sandbox first.'
        ],
        stepsAr: [
            'افتح إضافات كروم وأدوات البيانات.',
            'ثبّت الإضافات الموصى بها من الروابط.',
            'انسخ وصفة SOQL للكائن المطلوب.',
            'اقرأ شرح DML قبل التنفيذ.',
            'استخدم الأدوات للقراءة والتحقق؛ نفّذ التغييرات الجماعية في بيئة تجريبية أولاً.'
        ]
    },
    {
        id: 'hcp-portal',
        tile: 'HCP Portal',
        tileAr: 'بوابة مقدم الرعاية',
        intents: ['hcp app', 'invite tabs', 'qr'],
        phrase: 'When I want to choose tabs on the meeting invite HCP app, I open HCP Portal.',
        phraseAr: 'عندما أريد اختيار تبويبات تطبيق دعوة مقدم الرعاية، أفتح بوابة مقدم الرعاية.',
        steps: [
            'Open HCP Portal.',
            'Review which invite tabs are on.',
            'Keep entry pass and live QR on.',
            'Save.',
            'Open an invite link yourself to check what guests see.'
        ],
        stepsAr: [
            'افتح بوابة مقدم الرعاية.',
            'راجع التبويبات المفعّلة.',
            'أبقِ بطاقة الدخول وQR المباشر مفعّلين.',
            'احفظ.',
            'افتح رابط دعوة بنفسك وتأكد مما يراه الضيف.'
        ]
    }
];
