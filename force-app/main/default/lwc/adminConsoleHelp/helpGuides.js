/**
 * Detailed walkthroughs layered on top of HELP_ITEMS (same ids).
 * `shot` is a file name inside the AdminHelpShots static resource (real production screens, 25 Oct 2026).
 * English steps here replace the short English steps; Arabic keeps stepsAr and shows the same screenshots.
 */
export const HELP_GUIDES = {
    'field-app-manager': {
        overview:
            'Field App Manager is the single switchboard for what every field user sees. It controls the Home widgets, which performance rings appear, which planner tools are offered, whether Field AI and Class Engine are on, and which request types reps can raise. The same flags are read by Lightning, Salesforce mobile and the offline APK, so one save changes all three.',
        overviewAr:
            'مدير تطبيق الميدان هو لوحة التحكم الموحدة لما يراه كل مستخدم ميداني: ودجات الصفحة الرئيسية، حلقات الأداء، أدوات المخطط، ذكاء الميدان، محرك التصنيف، وأنواع الطلبات. الإعداد نفسه يُقرأ في لايتنينج وتطبيق الجوال والتطبيق دون اتصال.',
        affects: 'Every field user (MSR, DSM, ASM and CHC reps) on Lightning, Salesforce mobile and the APK.',
        before: [
            'Agree the change with the business owner; a hidden widget disappears for everyone at once.',
            'Know whether the APK users are online; offline devices pick up the new flags on their next sync.'
        ],
        steps: [
            {
                text: 'Open Admin Console and click the Field App Manager card.',
                detail: 'The module opens in a panel. Sections are listed top to bottom: Home, Your performance, Planner tools, Field AI, Class Engine, Requests. Each section has its own Save button.',
                shot: '01-field-app-manager.jpg'
            },
            {
                text: 'In Home, switch widgets on or off.',
                detail: 'Home office messages, Be in the know, Accounts nurturing engine, Your performance, Today\'s plan, Next best customer and Reports. Active (blue) means the widget shows on the field home page. Click Save in the Home section header; Save stays grey until you change something.'
            },
            {
                text: 'In Your performance, pick the measuring rings.',
                detail: 'These rings appear only when the Your performance widget is on. Keep at least one ring on, otherwise the section would show empty. Save the section.'
            },
            {
                text: 'In Planner tools, choose the planner actions reps get.',
                detail: 'Map / route, Copy previous plan, Add meeting and Time off. Turning one off removes the button from the planner on every device.'
            },
            {
                text: 'Turn Field AI and Class Engine on or off.',
                detail: 'Class Engine off hides the Class Engine tab and stops reps proposing new classes. It does not delete existing classes or cycles.'
            },
            {
                text: 'In Requests, enable Requests and tick the allowed request types.',
                detail: 'For example Medical + Device, Scientific material, Follow-up, Other. The detailed list of request types and who may create them is maintained in Service Request Types.'
            },
            {
                text: 'Check the result on a rep device.',
                detail: 'Open the field app as a rep (or ask one) and refresh. Lightning updates on reload; the APK updates on its next sync.'
            }
        ],
        tips: [
            'Each section saves independently. If you edit two sections, press Save in both.',
            'Use this module for on/off switches. Use Co-pilot app tabs to change which tabs the app shows.'
        ],
        cautions: ['Changes apply to every field user immediately; there is no per-territory override here.'],
        related: ['copilot-tabs', 'service-request-types', 'visit-tabs']
    },
    'hcp-portal': {
        overview:
            'HCP Portal controls the guest app doctors open from a meeting invitation (/meet). You choose which tabs guests see. The entry pass and live QR code are always on because they are how guests check in.',
        overviewAr:
            'بوابة مقدم الرعاية تتحكم في تطبيق الضيف الذي يفتحه الطبيب من دعوة الاجتماع. تختار التبويبات الظاهرة، وتبقى بطاقة الدخول وQR المباشر مفعّلة دائماً لأنها وسيلة تسجيل الحضور.',
        affects: 'External guests (HCPs) who open a meeting invite link.',
        before: ['Have a test invite link ready so you can see the result as a guest.'],
        steps: [
            {
                text: 'Open HCP Portal from Admin Console.',
                detail: 'The list shows each guest tab with a toggle: Products, News, Home shortcuts, Events and Requests.',
                shot: '02-hcp-portal.jpg'
            },
            {
                text: 'Switch tabs on or off.',
                detail: 'Events only shows content to guests who opened a valid invite or entered the PIN. Requests lets the guest ask for material or a follow-up.'
            },
            { text: 'Leave Entry pass and live QR on.', detail: 'They cannot be turned off; without them guests cannot check in at the venue.' },
            { text: 'Click Save.', detail: 'The change is live for the next page load of any invite link.' },
            { text: 'Open an invite link yourself and confirm what a guest sees.' }
        ],
        tips: ['Keep the guest app short. Fewer tabs makes the check-in pass easier to find on a phone.'],
        cautions: ['Anything you switch on is visible to people outside Zeta. Review News and Products content before enabling them.'],
        related: ['meetings-setup']
    },
    'copilot-tabs': {
        overview:
            'Co-pilot app tabs decides which tabs appear in each Co-pilot app: Field, Lead, Force and Care Coach. Meetings is not an app of its own; a speaker is simply an account with Is Speaker checked. Lifecycle Center stays off except for SFE profiles.',
        overviewAr:
            'تبويبات مساعد الطيار تحدد التبويبات الظاهرة في كل تطبيق: الميدان والقائد والقوة وكير كوتش. الاجتماعات ليست تطبيقاً مستقلاً، والمتحدث هو حساب مفعّل عليه خيار متحدث.',
        affects: 'Every user of the chosen app. The change applies to all reps of that app at once.',
        before: ['Decide which app you are changing. Field, Lead, Force and Care Coach each keep their own list.'],
        steps: [
            {
                text: 'Open Co-pilot app tabs.',
                detail: 'The App picker at the top shows Field Co-pilot by default, with one row per tab and an Active toggle.',
                shot: '03-copilot-app-tabs.jpg'
            },
            {
                text: 'Pick the app in the App dropdown.',
                detail: 'Field Co-pilot, Lead Co-pilot, Force Co-pilot or Care Coach. The list reloads with that app\'s tabs.'
            },
            {
                text: 'Turn tabs on or off.',
                detail: 'Field currently shows Home, Planner, Accounts, My Learning, Class Engine, CLM Presentations, Reports Hub, Pharmacy Sales, My Team, Reports and Dashboards. Meetings and Speakers are off.'
            },
            { text: 'Scroll down and click Save tabs.', detail: 'The order of tabs is fixed by the app; this screen only shows or hides them.' },
            { text: 'Open the target app and check the navigation bar.', detail: 'Reload the app. On mobile, pull to refresh or reopen the app.' }
        ],
        tips: ['If a rep says a tab is missing, check this screen first, then the rep\'s profile permissions.'],
        cautions: ['Hiding Home or Planner in Field Co-pilot removes the main working screens for every rep.'],
        related: ['field-app-manager', 'visit-tabs']
    },
    'visit-tabs': {
        overview:
            'Visit Tabs is a matrix of account type by visit section. It decides which sections a call report shows when a rep visits that type of account, for example Store Check and Make an Order only for pharmacies. Details is always on. Orders and Requests start on for every type.',
        overviewAr:
            'تبويبات الزيارة جدول يربط نوع الحساب بأقسام تقرير الزيارة، مثل فحص المخزن وإنشاء طلب للصيدليات فقط. قسم التفاصيل مفعّل دائماً.',
        affects: 'Every visit a rep opens for an account of that record type.',
        before: ['Know the account record type you want to change (HCP, HCO, Pharmacy, Distributor, Business Account, Person Account, Business Contact).'],
        steps: [
            {
                text: 'Open Visit Tabs.',
                detail: 'Rows are account types; columns are sections: Details, Affiliations, Attendees, Products, Dispense, Store Check, Make an Order, Presentations (scroll right for Orders and Requests).',
                shot: '04-visit-tabs.jpg'
            },
            {
                text: 'Find the row for the account type.',
                detail: 'Person Account appears twice because there are two record types with the same label. Change both rows the same way unless you know which one you need.'
            },
            {
                text: 'Tick or untick the sections that type needs.',
                detail: 'Typical setup: Pharmacy gets Store Check, Make an Order and Presentations; doctors and institutions get Affiliations, Attendees, Products, Dispense and Presentations.'
            },
            { text: 'Click Save at the top right.', detail: 'The button reads Saved once nothing is pending.' },
            { text: 'Open a visit for an account of that type and confirm the sections.' }
        ],
        tips: ['Untick a section rather than hiding the whole Visit tab; reps still need Details to log the call.'],
        cautions: ['Removing Products or Presentations from a type stops reps recording product details or CLM for those visits.'],
        related: ['copilot-tabs', 'clm']
    },
    clm: {
        overview:
            'CLM (closed-loop marketing) holds the presentation decks reps show during visits. You upload HTML or PDF slides, link them to a product and target them to territories so only the right reps see them.',
        overviewAr: 'إدارة العروض تحفظ العروض التي يعرضها المندوب أثناء الزيارة. ترفع شرائح HTML أو PDF وتربطها بمنتج وتوجهها للأقاليم.',
        affects: 'Reps in the targeted territories, in the CLM Presentations tab and inside visits.',
        before: [
            'Have the approved deck ready: a PDF, or a zipped HTML package.',
            'Know the product and territories the deck is for.'
        ],
        steps: [
            {
                text: 'Open CLM.',
                detail: 'The list shows every deck with format (HTML or PDF), slide count, product, status, and Edit / Deactivate actions. Use Filter to narrow the list.',
                shot: '05a-clm-list.jpg'
            },
            {
                text: 'Click New Presentation to start the 3-step wizard.',
                detail: 'Step 1 asks for the format (PDF or HTML), then name and product.',
                shot: '05b-clm-new-presentation.jpg'
            },
            {
                text: 'Upload the files.',
                detail: 'Choose Upload Files. Salesforce stores the file as soon as you pick it, so pick only the final approved version.'
            },
            { text: 'Set territory targeting.', detail: 'Tick the territories (or a whole line) that should see the deck, then finish the wizard.' },
            {
                text: 'Confirm a rep in that territory can see it.',
                detail: 'Open CLM Presentations as that rep, or check from a visit. To withdraw a deck later, use Deactivate rather than deleting it so visit history keeps the link.'
            }
        ],
        tips: ['Use Edit on an existing deck to replace slides instead of creating a duplicate deck.'],
        cautions: ['Uploading stores the file in the org immediately; cancel the wizard if you picked the wrong file and remove it from Files.'],
        related: ['visit-tabs', 'products-manager']
    },
    'rating-layouts': {
        overview:
            'Rating Layouts defines the questions on the field rating form, at three levels: Account, Account Territory and Account Territory Product. Ratings feed Class Engine, so the questions must match the SFE design.',
        overviewAr: 'تخطيطات التقييم تحدد أسئلة نموذج التقييم على ثلاثة مستويات: الحساب، الحساب والإقليم، الحساب والإقليم والمنتج. التقييمات تغذي محرك التصنيف.',
        affects: 'Every rep who rates an account (HCP or HCO) and the Class Engine scoring that uses those ratings.',
        before: ['Get the agreed question list from SFE, including the answer type for each (dot scale, text, etc.).'],
        steps: [
            {
                text: 'Open Rating Layouts.',
                detail: 'You see the deployed layouts (Standard HCO Ratings, Standard HCP Ratings) with how many Account, Territory and Product fields each has. Use New Layout to start from scratch.',
                shot: '06a-rating-layouts.jpg'
            },
            {
                text: 'Open a layout and choose the level tab.',
                detail: 'Account, Account Territory, or Account Territory Product ratings. The field picker on the side lists available fields with their type (dotScale, textValue).',
                shot: '06b-rating-layout-editor.jpg'
            },
            { text: 'Add, remove or reorder questions.', detail: 'The live preview shows the form exactly as the rep sees it.' },
            { text: 'Save the layout.' },
            { text: 'Open an account\'s Ratings tab to verify.', detail: 'Check an HCP for the HCP layout and an HCO for the HCO layout.' }
        ],
        tips: ['Change the layout before a Class Engine cycle starts, not during one, so all reps rate on the same questions.'],
        cautions: ['Removing a question hides it from the form; ratings already captured on that field are kept but no longer updated.'],
        related: ['sfe-approvers', 'promo-grid']
    },
    'learning-module-management': {
        overview:
            'Learning Module Management is where you create courses and learning material, attach files or links, set dates, and assign them to territories or people. Quizzes live under their parent course.',
        overviewAr: 'إدارة وحدات التعلم لإنشاء الدورات والمواد التعليمية وإرفاق الملفات والروابط وتحديد التواريخ وتعيينها للأقاليم أو الأشخاص.',
        affects: 'Users who receive the assignment, in My Learning.',
        before: ['Have the material (file or link), the course dates, and the list of territories or people.'],
        steps: [
            {
                text: 'Open Learning Module Management.',
                detail: 'The list shows every course with filters for Search, Type, Status and Territory. Click New Material to create one.',
                shot: '07a-learning-list.jpg'
            },
            {
                text: 'Open a course to edit it.',
                detail: 'Expand a course (for example CHC) to see its quizzes. Edit parent course shows title, description, duration, start/end dates and Active.',
                shot: '07b-learning-course-edit.jpg'
            },
            { text: 'Add the file or link and click Save changes.' },
            {
                text: 'Assign it in Assigned Territories.',
                detail: 'Tick territories; cascade includes everything under a selected territory. The course card shows the number of assignments.'
            },
            { text: 'Confirm it appears in My Learning for one of the assigned reps.' }
        ],
        tips: ['A course counts assignments to users and to territories. If the card says 2 assigned but no territories are ticked, the assignments are to individual users.'],
        cautions: ['Unticking Active hides the course from everyone, including people midway through it.'],
        related: ['quiz-management']
    },
    'quiz-management': {
        overview:
            'Quiz Management lists every quiz with its status and parent course, and opens a question editor with single-choice options, points and a live preview. Quizzes are taken through the course they belong to.',
        overviewAr: 'إدارة الاختبارات تعرض كل اختبار وحالته ودورته، وتفتح محرر الأسئلة مع الخيارات والدرجات والمعاينة الحية.',
        affects: 'Users assigned to the parent course; quiz scores can feed the quiz KPI.',
        before: ['Create or pick the parent course in Learning Module Management first.'],
        steps: [
            {
                text: 'Open Quiz Management.',
                detail: 'Search by title or filter by status. Each row has Edit Questions and Open Record. Click New Quiz to create one.',
                shot: '08a-quiz-list.jpg'
            },
            {
                text: 'Click Edit Questions.',
                detail: 'The Quiz Question Configuration editor opens below the list (scroll down; it does not jump there by itself). It shows the question count and total points.',
                shot: '08b-quiz-question-editor.jpg'
            },
            { text: 'Add or edit questions and options.', detail: 'Use Add question, mark the correct option, and set points. Edit JSON is available for bulk edits.' },
            { text: 'Click Save, then set the quiz Active when it is ready.' },
            { text: 'Make sure the parent course is assigned in Learning Module Management.' }
        ],
        tips: ['Check the live preview on a phone-sized window; long options wrap on mobile.'],
        cautions: ['Editing questions of a quiz people already took changes future attempts only; old scores stay as they were.'],
        related: ['learning-module-management', 'kpi-targets']
    },
    'coaching-management': {
        overview:
            'Coaching Management holds the field coaching templates managers fill when they coach a rep during a visit. You design the sections and questions, activate the template, and managers pick it from Create Coaching Event.',
        overviewAr: 'إدارة التدريب الميداني تحفظ قوالب التدريب التي يملؤها المدير عند مرافقة المندوب. تصمم الأقسام وتفعّل القالب.',
        affects: 'Managers (DM, AM) who create coaching events.',
        before: ['Agree the coaching form with Training / L&D.'],
        steps: [
            {
                text: 'Open Coaching Management.',
                detail: 'Templates are listed with type and status, plus Open and Clone actions, search, a status filter and New Template.',
                shot: '09-coaching-management.jpg'
            },
            { text: 'Open a template, or Clone one to start from it.', detail: 'Cloning keeps the original untouched while you work on the copy.' },
            { text: 'Design the sections and questions managers will fill.' },
            { text: 'Set the template Active.', detail: 'Deactivate leftovers (for example an unused "(Copy)" template) so managers do not pick the wrong one.' },
            { text: 'From a visit, open Create Coaching Event and confirm the template is offered.' }
        ],
        tips: ['Name templates by purpose (Visit Check, Business Support) so managers recognise them on mobile.'],
        cautions: [],
        related: ['territory-management']
    },
    'territory-management': {
        overview:
            'Territory Management has three tabs. Product Lines shows each line with its brands, districts, positions and users. Territories shows the hierarchy tree (Head Office > Business Unit > Line > District > Territory) and can export the organogram. Users lets you create, edit, activate or deactivate field users and set OTP passwords.',
        overviewAr: 'إدارة الأقاليم فيها ثلاثة تبويبات: خطوط المنتجات، شجرة الأقاليم مع تصدير الهيكل، والمستخدمون لإنشاء وتعديل وتفعيل المستخدمين.',
        affects: 'Who sees which accounts, My Team for managers, plan cycles and every report built on territory.',
        before: [
            'Have the employee code and the target territory ready.',
            'For moves between lines, check with SFE because it changes which accounts and products the rep sees.'
        ],
        steps: [
            {
                text: 'Open Territory Management and choose a tab.',
                detail: 'Product Lines: filter by Business Unit. Each card shows brands, details, samples, districts, positions and users, with Manage Products and Edit Line.',
                shot: '10a-territory-product-lines.jpg'
            },
            {
                text: 'In Territories, find the territory in the tree.',
                detail: 'Use the filters to narrow by line. Download organogram exports the tree as CSV, one row per person in a seat (a vacant seat has one empty row), with Level, Territory, Title, Holder and Holder Username. Brand Managers and Group Brand Leads appear once, on their Marketing Seat. Download full organogram (bricks) gives the Drive layout with one row per 702 brick per position. Tick Show training territories only when you need them.',
                shot: '10b-territory-tree.jpg'
            },
            {
                text: 'In Users, find the person.',
                detail: 'Filter by status or search by name. From here you can Create User, Edit, Set OTP Password, and Activate / Deactivate selected users.',
                shot: '10c-territory-users.jpg'
            },
            { text: 'Edit the assignment and save.', detail: 'Assign the user to the territory (or move them). The parent territory decides the manager.' },
            { text: 'Confirm the rep appears under the right manager in My Team.' }
        ],
        tips: [
            'A Brand Manager or Group Brand Lead has two seats: their own Marketing Seat box, which is their place in the organogram, and an access seat on their Line or Business Unit so they can see that team. The download lists only the Marketing Seat.',
            'In the tree, the Assigned User column shows who holds the seat\'s title; people below are a grey count. Use the Users tab for the full list.'
        ],
        cautions: [
            'The one-off buttons on Product Lines (Apply October line assignments, Apply CHC / GIT / CVM mirrors, Seat Brand Managers) rewrite assignments in bulk. Do not click them unless you are repeating that specific migration.',
            'Deactivating a user frees their territory seat; their accounts stay on the territory.'
        ],
        related: ['products-manager', 'plan-manager', 'sfe-approvers']
    },
    'sfe-approvers': {
        overview:
            'SFE Approvers decides which SFE person approves Class Engine cycles and new account requests for each business unit. When no approver matches a line, the fallback rule shown on the screen applies.',
        overviewAr: 'معتمدو SFE يحدد من يعتمد دورات محرك التصنيف وطلبات الحسابات الجديدة لكل وحدة أعمال.',
        affects: 'Who receives Class Engine and new-account approvals.',
        before: ['The SFE must be an active user.'],
        steps: [
            {
                text: 'Open SFE Approvers.',
                detail: 'Each row is an SFE with ticks for business units (or All lines) and for what they approve: Class Engine, New accounts. Widen the window if the New accounts column is cut off.',
                shot: '11-sfe-approvers.jpg'
            },
            { text: 'Use Add approver to search and add an SFE who is not listed.' },
            { text: 'Tick the business units they cover, or All lines.' },
            { text: 'Tick Class Engine, New accounts, or both.' },
            { text: 'Save, then open a pending cycle or account request to confirm it routes to them.' }
        ],
        tips: ['Give every business unit at least one approver so nothing falls to the fallback rule by accident.'],
        cautions: ['Removing an approver does not reassign items already waiting for them.'],
        related: ['rating-layouts', 'account-data-quality', 'meetings-setup']
    },
    'bricks-management': {
        overview:
            'Bricks Manager draws the IMS brick regions (702 micro bricks and 148 bricks) on a map. Outlines come from official CAPMAS districts. Once regions are right, Apply regions to sales places every distributor client in the brick that contains its location.',
        overviewAr: 'مدير الطوب يرسم مناطق طوب IMS (702 و148) على الخريطة من حدود الجهاز المركزي للتعبئة. بعد ضبطها، طبّق المناطق على المبيعات.',
        affects: 'Brick-level sales reporting and which brick each pharmacy belongs to.',
        before: ['Pharmacies need coordinates (from Distributors Management matching) before they can be placed in a brick.'],
        steps: [
            {
                text: 'Open Bricks Manager.',
                detail: 'The Egypt map shows every brick outline with a count of bricks that have a region (702/702).',
                shot: '12a-bricks-egypt.jpg'
            },
            {
                text: 'Switch between 702 micro bricks and 148 bricks.',
                detail: 'The 148 view groups micro bricks into the larger IMS bricks.',
                shot: '12c-bricks-148.jpg'
            },
            {
                text: 'Click a brick to inspect or edit it.',
                detail: 'The side panel shows name, code, parent and city. Edit the outline on the map if needed, or Suggest from OSM for one brick, then save. The outline is stored on the brick record as GeoJSON.',
                shot: '12b-bricks-abbaseya.jpg'
            },
            {
                text: 'Apply regions to sales when the banner asks.',
                detail: 'The banner appears when regions changed after sales lines were placed. This updates the brick on every sales line, so run it after you finish editing, not after each brick.'
            }
        ],
        tips: ['Zoom into a dense area (for example Cairo) to check that outlines follow real streets.'],
        cautions: ['Apply regions to sales writes to every sales line. Run it once at the end of an editing session.'],
        related: ['distributors-management', 'integrations-management']
    },
    'products-manager': {
        overview:
            'Products Manager shows the product catalog as a tree (Brand > Detail > Sample or Brand Reminder, with codes). Here you add new products, change product details and prices, and align each product to territories so reps only see the products of their line.',
        overviewAr: 'مدير المنتجات يعرض الكتالوج كشجرة (علامة > تفصيل > عينة أو تذكير بالعلامة). منه تضيف منتجات جديدة وتعدل بياناتها وأسعارها وتحاذيها للأقاليم.',
        affects: 'Which products reps see in visits, samples, orders and plans, and the public price sales policy uses.',
        before: [
            'For a new product: its type, the brand (or detail) it belongs to, the product code agreed with sales operations, and the line.',
            'Know the territories (or line) it should be aligned to.'
        ],
        steps: [
            {
                text: 'Open Products Manager and find the product.',
                detail: 'Browse the catalog tree or search by name or code.',
                shot: '13a-products-catalog.jpg'
            },
            {
                text: 'To add a product, click New product.',
                detail: 'Pick the type first. A Detail belongs to a Brand; a Sample or Brand Reminder belongs to a Brand or a Detail; a Brand is top level. Fill name, product code, sales line, strength, form, sales unit, box quantity and public price.'
            },
            {
                text: 'To change a product, select it and click Edit product.',
                detail: 'You can change the name, line, pack details, price, image, Show in HCP app and Active. The product code and external ID are fixed after creation.'
            },
            {
                text: 'Click Save product, then align it.',
                detail: 'The new or edited product is selected for you. The right side shows Territory Distribution; with cascade on, ticking a district ticks every territory under it. Click Save Alignment.',
                shot: '13b-products-alignment.jpg'
            },
            { text: 'Open a rep\'s visit or plan in that territory and confirm the product appears.' }
        ],
        tips: [
            'Leave External ID blank to use the product code, which matches the existing catalog.',
            'The public price is saved in the standard price book; sales policy uses it for non-tender value.'
        ],
        cautions: [
            'Check the product code with sales operations before saving: distributor sales and imports match on it, and it cannot be changed here afterwards.',
            'Untick Active instead of deleting. Inactive products leave the catalog, visits and orders; their history stays.',
            'Unaligning a product hides it from reps in those territories immediately, including in open plans.'
        ],
        related: ['territory-management', 'promo-grid', 'sample-logistics']
    },
    'promo-grid': {
        overview:
            'Promo Grid Management sets, for each line, how product weights, specialty focus and class targeting are split. Each section must total 100%. Class Engine uses these weights. You can edit on screen or round-trip an Excel workbook.',
        overviewAr: 'إدارة شبكة الترويج تحدد لكل خط أوزان المنتجات والتخصصات والفئات، ويجب أن يجمع كل قسم 100٪. يستخدمها محرك التصنيف.',
        affects: 'Class Engine results and call targeting for the line.',
        before: ['Get the agreed weights from the brand / SFE team.'],
        steps: [
            {
                text: 'Open Promo Grid Management and select a line.',
                detail: 'The tree shows each line with Assigned / Vacant and a weight meter. A line showing 0% has no weights yet.',
                shot: '14a-promo-grid.jpg'
            },
            { text: 'Edit product weights, specialty focus and class targeting.', detail: 'Each section must reach exactly 100% before it can be saved.' },
            {
                text: 'For bulk edits use Excel.',
                detail: 'Download template gives a blank workbook; Export gives current values. Both have Products, Specialties and Classes sheets with a Line column.'
            },
            {
                text: 'Click Import, upload the workbook, and read the preview.',
                detail: 'A section is replaced only when it has at least one percentage filled. Apply import stays disabled until a file is attached.',
                shot: '14b-promo-grid-import.jpg'
            },
            { text: 'Apply, then run Class Engine for the line.' }
        ],
        tips: ['Export first, edit that file, and re-import; it keeps line names spelled exactly as the system expects.'],
        cautions: ['If the preview shows every line as "(unnamed)" with errors, stop and do not apply; the line names in the file did not match.'],
        related: ['rating-layouts', 'products-manager']
    },
    'sample-logistics': {
        overview:
            'Sample Logistics tracks sample requests from reps, allocation of lots, and each rep\'s on-hand inventory with lot and expiry. From here you transfer stock between reps or take returns.',
        overviewAr: 'لوجستيات العينات تتابع طلبات العينات وتخصيص الدفعات ومخزون كل مندوب بالدفعة والصلاحية.',
        affects: 'Rep sample stock and what they can drop during visits.',
        before: ['Have lot numbers and expiry dates from Supply Chain.'],
        steps: [
            {
                text: 'Open Sample Logistics on the Requests tab.',
                detail: 'The New request form (product, quantity, preferred rep, notes) sits above the request queue with status (for example Allocated).',
                shot: '15a-sample-requests.jpg'
            },
            { text: 'Open a request and allocate lots.', detail: 'Allocate by expiry, earliest first.' },
            {
                text: 'Switch to Rep inventory to check stock.',
                detail: 'Each line shows lot, expiry and quantity with Transfer and Return actions.',
                shot: '15b-sample-inventory.jpg'
            },
            { text: 'Transfer or return stock as needed.' },
            { text: 'Cancel a request only after Supply Chain confirms it will not be filled.' }
        ],
        tips: ['Review Rep inventory monthly for lots past expiry and return them.'],
        cautions: ['Expired lots are not flagged automatically; check the expiry column yourself.'],
        related: ['products-manager']
    },
    'plan-manager': {
        overview:
            'Plan Manager shows plan coverage per month for the whole field force. The year view gives a count of employees with a plan each month; drilling into a month lists each employee with HAS PLAN / NO PLAN and their account targets, with Edit, Create plan and Copy Plans.',
        overviewAr: 'مدير الخطط يعرض تغطية الخطط شهرياً، ويفصّل كل شهر لكل موظف مع وجود خطة أو لا، مع التعديل والإنشاء والنسخ.',
        affects: 'Rep monthly call plans and plan-based KPIs.',
        before: ['Check the destination month is empty, or meant to be replaced, before copying.'],
        steps: [
            {
                text: 'Open Plan Manager on the year view.',
                detail: 'Each month shows employees with a plan out of the total (for example 19 / 694). CURRENT marks this month.',
                shot: '16a-plan-manager-year.jpg'
            },
            {
                text: 'Click a month to drill down.',
                detail: 'Each row: employee, territory, HAS PLAN / NO PLAN, and account targets.',
                shot: '16b-plan-manager-october.jpg'
            },
            { text: 'Use Edit to change a plan, or Create plan for someone without one.' },
            {
                text: 'Use Copy Plans to roll a month forward.',
                detail: 'Copy overwrites targets in the destination month.'
            },
            { text: 'Confirm the coverage count for the month went up.' }
        ],
        tips: ['A low coverage percentage early in the month usually means reps have not submitted yet; chase via managers.'],
        cautions: ['Copy Plans replaces destination targets. Never copy over a month reps are already working.'],
        related: ['call-target-rules', 'territory-management']
    },
    'call-target-rules': {
        overview:
            'Call Target Rules reduces a rep\'s call target when they are away: time off, long leave, meetings. You choose which time-off types count, how many days are allowed before pro-rating starts, the lowest target, and what counts as long leave.',
        overviewAr: 'قواعد هدف المكالمات تخفض هدف المندوب عند الغياب: الإجازات والإجازة الطويلة والاجتماعات.',
        affects: 'Monthly call targets and call-rate KPIs for every rep.',
        before: ['Agree the pro-rating rule with SFE before the month starts.'],
        steps: [
            {
                text: 'Open Call Target Rules.',
                detail: 'The rule shows Adjustment Active, counted days before pro-rating, lowest target, long leave days, and the list of time-off types. A worked example explains the math.',
                shot: '17-call-target-rules.jpg'
            },
            { text: 'Tick the time-off types that should reduce the target.' },
            { text: 'Set counted days before pro-rating, lowest target and long-leave days.', detail: 'Ignore "Calls to subtract (no longer used)".' },
            { text: 'Click Save rule.' },
            { text: 'Open the planner for a rep with leave this month and check the reduced target.' }
        ],
        tips: ['Read the worked example after each change; it recalculates with your numbers.'],
        cautions: ['Changing the rule mid-month recalculates targets for the whole month.'],
        related: ['plan-manager', 'kpi-targets', 'planner-rules']
    },
    'kpi-targets': {
        overview:
            'KPI Targets lists every metric per role (Medical Sales Rep, District Manager, Area Manager, National Sales Manager, Brand Manager, CHC roles). Each metric has a target percentage, period, count source, scope and a plain-language numerator / denominator.',
        overviewAr: 'أهداف مؤشرات الأداء تعرض كل مؤشر لكل دور مع نسبة الهدف والفترة ومصدر العد والنطاق.',
        affects: 'Field and Lead scorecards for that role.',
        before: ['Agree target changes with the business owner; scorecards change for everyone in the role.'],
        steps: [
            {
                text: 'Open KPI Targets.',
                detail: 'Metrics are grouped by role. Each card shows the target %, period, source and scope.',
                shot: '18-kpi-targets.jpg'
            },
            { text: 'Find the role and metric.' },
            { text: 'Edit the target percentage (or use Add metric / Remove).' },
            { text: 'Click Save all.' },
            { text: 'Refresh Field or Lead KPIs for someone in that role and confirm.' }
        ],
        tips: ['Read the numerator / denominator text; it tells you exactly what the KPI counts.'],
        cautions: ['Reset to framework sits next to Save all and replaces every target with the default. Do not click it unless you mean to start over.'],
        related: ['call-target-rules', 'quiz-management']
    },
    'sales-policy': {
        overview:
            'Sales Policy holds the rules used to turn distributor sales into achievement: the distribution ceiling cap, actual vs target share split, whether tender sales count, the public-price calculation for non-tender quantities, and brands that use tender price as an exception.',
        overviewAr: 'سياسة المبيعات تحدد قواعد تحويل مبيعات الموزعين إلى إنجاز: سقف التوزيع، تقسيم الحصة، المناقصات، وسعر الجمهور.',
        affects: 'Sales achievement figures and exports.',
        before: ['Get finance / sales-ops agreement before changing any number.'],
        steps: [
            {
                text: 'Open Sales Policy.',
                detail: 'The Org Default policy shows ceiling cap, actual share, target share, exclude tender, non-tender quantity × public price, and tender-price exception brands.',
                shot: '19-sales-policy.jpg'
            },
            { text: 'Review the ceiling and share split.' },
            { text: 'Review tender exclusion and the exception brands (for example Zeta Colest).' },
            { text: 'Click Save sales policy.' },
            { text: 'Export a known month in Export month and confirm the numbers you expect.' }
        ],
        tips: [],
        cautions: ['The policy applies to calculations from the save onward; months already exported are not rewritten.'],
        related: ['sales-export-month', 'monthly-data-pack']
    },
    'monthly-data-pack': {
        overview:
            'Monthly data pack loads a month of data in one go: distributor and POS sales, leave, time off and historical visits. Files are read in your browser first, recognised by type, and previewed before anything is imported.',
        overviewAr: 'حزمة بيانات الشهر تحمّل بيانات شهر كامل: المبيعات والإجازات والزيارات التاريخية. تُقرأ الملفات في المتصفح وتُعرض معاينة قبل الاستيراد.',
        affects: 'Sales, time-off and visit history for the month.',
        before: ['Collect the month\'s files. Accepted: .zip, .xlsx, .xls, .xlsm, .csv.'],
        steps: [
            {
                text: 'Open Monthly data pack.',
                detail: 'Drop the month zip or the individual spreadsheets on the drop zone.',
                shot: '20a-data-pack-empty.jpg'
            },
            {
                text: 'Read the preview for each file.',
                detail: 'Each file shows what it was recognised as (for example POS sales), row count, a fingerprint, the report month (filled from the file dates), and rows rejected.',
                shot: '20b-data-pack-preview.jpg'
            },
            { text: 'Fix the report month if it was guessed wrong.' },
            { text: 'Click Import selected only when every preview looks right.', detail: 'Use Start over to clear and try again.' },
            { text: 'If a batch reports failed rows, download the error CSV, fix and re-import.' }
        ],
        tips: ['The fingerprint stops the same file being loaded twice.'],
        cautions: ['Importing writes to production data. Check the report month before you click Import.'],
        related: ['sales-export-month', 'distributors-management']
    },
    'sales-export-month': {
        overview: 'Export month is where you download pharmacy sales data: one month of distributor sales (Ibn Sina, POS, Elezaby, Egydrug, Ebda, Sofico) consolidated into one Excel file, with pharmacy, product, quantity and revenue on each line, and where the sale landed: its 702 and 148 bricks, how the brick was chosen, whether it is linked to a CRM pharmacy, and the line, territory and rep the 702 brick is aligned to. Run it once per month you need.',
        overviewAr: 'تصدير الشهر ينزّل مبيعات الموزعين لشهر واحد في ملف إكسل.',
        affects: 'Nothing; it is read-only.',
        before: ['The month must have distributor sales loaded and matched.'],
        steps: [
            {
                text: 'Open Export month.',
                detail: 'Pick any day inside the report month, then a distributor or All.',
                shot: '21a-export-month.jpg'
            },
            { text: 'Click Export month.' },
            { text: 'Open the Excel file and check product, quantity and revenue on each line.' },
            {
                text: 'Use the mapping columns to see where each sale landed.',
                detail: 'Linked CRM pharmacy is Y when the distributor client is matched to a pharmacy account; when N, Pharmacy shows the distributor\'s own client name and code. 702 brick and 148 brick come from the client\'s location (Brick source says how). Line, Territory and Rep come from the brick alignment, limited to the lines that carry the product.'
            }
        ],
        tips: [
            '"Nothing to export for that month and distributor" means no matched sales exist for that month yet; check Distributors Management.',
            'A product on more than one line (for example a GIT brand that GIT-SALES also carries) lists every line, territory and rep, separated by semicolons. A territory that only holds part of the brick shows its share, for example (50%).',
            'Line, Territory and Rep are empty when the product has no sales line, the line has no position aligned to that brick, or the sale has no 702 brick. Rep is empty when the position is vacant.',
            'Doctors are not listed: sales are placed by brick, not by doctor.'
        ],
        cautions: [],
        related: ['sales-policy', 'distributors-management', 'monthly-data-pack']
    },
    'distributors-management': {
        overview:
            'Distributors Management imports distributor Excel files, matches each distributor client to a pharmacy account, and confirms product mapping. KPIs at the top show pharmacies mapped, products confirmed and rows needing review.',
        overviewAr: 'إدارة الموزعين تستورد ملفات الموزعين وتطابق كل عميل بصيدلية وتؤكد ربط المنتجات.',
        affects: 'Which pharmacy and brick each distributor sale lands on.',
        before: ['Have the distributor\'s native Excel file and know the report month.'],
        steps: [
            {
                text: 'Open Distributors Management on the Import tab.',
                detail: 'Upload the distributor Excel, set report month, leave report type on auto-detect. Prefer rows with address helps matching.',
                shot: '22a-distributors-import.jpg'
            },
            { text: 'Go to Registry and Product mapping to review matches.', detail: 'Confirm a suggested pharmacy only after checking name and address.' },
            {
                text: 'Check Batches for the import result.',
                detail: 'Each batch shows file name, status and counts.',
                shot: '22b-distributors-batches.jpg'
            },
            { text: 'Repeat until Needs review is low and Pharmacies mapped is high.' }
        ],
        tips: ['Matching uses OpenStreetMap within 250 m unless a Google key is set.'],
        cautions: ['Max rows (pilot) limits each import to 200 rows. Clear it for a full monthly load.'],
        related: ['bricks-management', 'sales-export-month', 'monthly-data-pack']
    },
    'target-governance': {
        overview:
            'Target Governance raises alarms when a rep\'s visit frequency or target list changes more than an allowed percentage, and runs the end-of-month out-of-target queue that managers approve.',
        overviewAr: 'حوكمة الأهداف تنبه عند تغير التكرار أو قائمة الهدف أكثر من النسبة المسموحة، وتدير طابور نهاية الشهر.',
        affects: 'Managers who approve out-of-target proposals.',
        before: [],
        steps: [
            {
                text: 'Open Target Governance.',
                detail: 'Deviation alarms show frequency and list-change thresholds (default 10% / 10%).',
                shot: '23b-target-governance-fixed.jpg'
            },
            { text: 'Set the thresholds and click Save alarm thresholds.' },
            { text: 'Use Build queue for me to load the out-of-target queue for the month.' },
            { text: 'Work proposals in order: DM, then FI, then business unit.' }
        ],
        tips: ['"No proposals" means nobody broke the thresholds this month.'],
        cautions: [],
        related: ['target-master-lists', 'plan-manager']
    },
    'account-management': {
        overview:
            'Account Management handles master data in bulk: account and affiliation counts, Import / Modify (upsert by External ID), Business Units, Export, and Duplicate review. It also has Wipe & Load, which deletes all accounts and affiliations before reloading.',
        overviewAr: 'إدارة الحسابات للبيانات الأساسية بالجملة: الاستيراد والتعديل والتصدير ومراجعة التكرار. تبويب المسح والتحميل يحذف كل الحسابات.',
        affects: 'Every account and affiliation in the org.',
        before: ['Export a backup first (Export tab) before any import.'],
        steps: [
            {
                text: 'Open Account Management and read the counts.',
                detail: 'Accounts and Affiliations totals; use Refresh counts after a load.',
                shot: '24a-accounts-wipe-load.jpg'
            },
            {
                text: 'For changes, use Import / Modify.',
                detail: 'Upload Organizations and/or Doctors workbooks. Keep Scan for name + location duplicates ticked. Import / Modify upserts straight away; there is no preview step.',
                shot: '24c-accounts-import-modify.jpg'
            },
            { text: 'For a backup or analysis, use Export.', detail: 'Export Accounts & Affiliations builds a large Excel file (about a minute).' },
            {
                text: 'Check Duplicate review after an import.',
                shot: '24d-accounts-duplicates.jpg'
            }
        ],
        tips: ['For targeted updates of the master or target list, Target & Master Lists is safer: it upserts only.'],
        cautions: [
            'Wipe & Load deletes every account and affiliation before reloading. Use it only for a planned full reset, never for a fix.',
            'Import / Modify has no preview. Test the file on a small sample first.'
        ],
        related: ['target-master-lists', 'account-data-quality']
    },
    'account-data-quality': {
        overview:
            'Account data quality runs two scans on existing accounts. Duplicates finds likely duplicates by name and location. Nurture fills missing data from Google Places and Vezeeta. Both produce proposals that SFE must greenlight before anything changes.',
        overviewAr: 'جودة بيانات الحسابات تشغّل فحص التكرار وفحص الإثراء من جوجل وفيزيتا، وتنتج مقترحات تحتاج موافقة SFE.',
        affects: 'Account records, only after greenlight.',
        before: [],
        steps: [
            {
                text: 'Open the Duplicates tab.',
                detail: 'Choose account types (HCP person, HCP clinic, Pharmacy, HCO). Tick Show possible to include 50-69% matches. Click Run duplicate scan.',
                shot: '25a-data-quality-duplicates.jpg'
            },
            {
                text: 'Or open Nurture.',
                detail: 'Pick sources (Google Places, Vezeeta) and whether to skip accounts reviewed in the last 30 days, then Run nurture scan.',
                shot: '25b-data-quality-nurture.jpg'
            },
            { text: 'Click Refresh when the batch finishes and review the proposals.' },
            { text: 'Select rows. For duplicates choose Mark or Merge; for nurture accept the fields you want.' },
            { text: 'Greenlight the selection, or dismiss the rest.' }
        ],
        tips: ['Start with Pharmacy; it has the most duplicates from distributor files.'],
        cautions: ['Merge cannot be undone from this screen.'],
        related: ['account-management', 'sfe-approvers']
    },
    'target-master-lists': {
        overview:
            'Target & Master Lists imports and exports two files: Organizations Final Master List (organizations and doctors) and Target List (All Team, the call-plan targets). Import is upsert only; nothing is wiped.',
        overviewAr: 'قوائم الهدف والمستر تستورد وتصدر ملف المستر وقائمة الهدف. الاستيراد تحديث فقط دون مسح.',
        affects: 'Account master data and territory target links.',
        before: ['Export the current list first and edit that file.'],
        steps: [
            {
                text: 'Open Target & Master Lists.',
                detail: 'Counts show accounts, territory links and call-plan targets.',
                shot: '26a-target-master.jpg'
            },
            {
                text: 'Export to get the current file.',
                detail: 'Export target list and Export master list each download an Excel file and show how many rows were exported.',
                shot: '26b-target-export-complete.jpg'
            },
            {
                text: 'Edit the file and choose Import.',
                detail: 'The file is parsed in the browser first and shows row counts (for example 64151 target rows) before you confirm.',
                shot: '26d-target-master-roundtrip-parse.jpg'
            },
            { text: 'Confirm the import.', detail: 'Vacant employee codes (vac-*) are skipped.' }
        ],
        tips: ['Compare the parsed row count with the export count; they should match if you only edited values.'],
        cautions: ['Use Account Management Wipe & Load only for a full reset; this screen is the safe way to update.'],
        related: ['account-management', 'target-governance']
    },
    'public-holidays': {
        overview: 'Public Holidays lists company holidays. A holiday closes the day in the planner so reps cannot plan visits on it, and it is excluded from call targets.',
        overviewAr: 'العطلات الرسمية تغلق اليوم في المخطط وتستثنيه من أهداف المكالمات.',
        affects: 'Every rep planner and working-day counts.',
        before: ['Have the official dates. Movable holidays (Eids) need the actual date each year.'],
        steps: [
            {
                text: 'Open Public Holidays.',
                detail: 'Each holiday shows name, date, whether it repeats every year or is one-off, and status. Use New Holiday, Edit or Delete.',
                shot: '27-public-holidays.jpg'
            },
            { text: 'Click New Holiday, enter name and date, and choose yearly or one-off.' },
            { text: 'Save.' },
            { text: 'Open a rep planner on that date and confirm it is closed.' }
        ],
        tips: ['Multi-day holidays (Eid al-Fitr, Eid al-Adha) need one entry per day.'],
        cautions: ['One-off holidays do not roll over; add next year\'s dates each year.'],
        related: ['planner-rules', 'call-target-rules']
    },
    'planner-rules': {
        overview:
            'Planner Rules sets working days and what happens when two things overlap in the planner (visit, time off, meeting, holiday): Allow, Warn or Block. Rules can be set org-wide or more specifically by line, title, profile or user.',
        overviewAr: 'قواعد المخطط تحدد أيام العمل وما يحدث عند التداخل (زيارة، إجازة، اجتماع، عطلة): سماح أو تحذير أو منع.',
        affects: 'Planner behaviour for everyone in the chosen scope.',
        before: ['Decide the scope. The most specific rule wins: User > Line + Title > Title > Profile > Line > BU > Org.'],
        steps: [
            {
                text: 'Open Planner Rules and pick the scope tab.',
                detail: 'Org-wide, Line, Line + Title, Title, Profile or User.',
                shot: '28-planner-rules.jpg'
            },
            { text: 'Tick working days.', detail: 'Egypt default is Saturday to Wednesday (weekend Thursday and Friday). Presets are available.' },
            { text: 'Set each overlap cell to Allow, Warn or Block.', detail: 'For example Visit vs Holiday: Block; Time off vs Meeting: Warn.' },
            { text: 'Save.' },
            { text: 'In the planner, try a conflicting slot and confirm the behaviour.' }
        ],
        tips: ['Start with Org-wide and add narrower rules only for exceptions.'],
        cautions: [],
        related: ['public-holidays', 'call-target-rules']
    },
    'meetings-setup': {
        overview:
            'Meetings Setup defines meeting types (for example KOL Roundtable, Speaker Meeting, Advisory Board), who can create each, which screens they show, and the spend approval chain per department. Preview as user shows the chain a given person and amount would get.',
        overviewAr: 'إعداد الاجتماعات يحدد أنواع الاجتماعات ومن ينشئها والشاشات الظاهرة وسلسلة الموافقة لكل قسم.',
        affects: 'Who can create meetings and who must approve the spend.',
        before: ['Have the approved chain from Finance (roles and amount thresholds).'],
        steps: [
            {
                text: 'On Meeting types, open a type.',
                detail: 'Set departments, territories, who can create it, and which screens (tabs) the meeting shows. Keep it Active.',
                shot: '29a-meeting-types.jpg'
            },
            {
                text: 'On Approval sequence, pick the department and chain.',
                detail: 'Sales, Marketing, Medical or L&D. Each step has a role and when it applies: Always, Above an amount, or From an amount. Use Add step, edit or delete.',
                shot: '29b-meeting-approvals.jpg'
            },
            { text: 'Use Preview as user to test a person and amount.' },
            { text: 'Save, then confirm Meetings stays off the field phone launcher.' }
        ],
        tips: [
            'A step with a minimum amount (for example CEO from 250,000) joins only when the planned cost reaches it.',
            'If actual cost ends up more than about 10% over the approved plan, approval restarts.'
        ],
        cautions: [],
        related: ['hcp-portal', 'sfe-approvers']
    },
    'service-request-types': {
        overview: 'Service Request Types lists every request type reps or HCPs can raise, with category, subtype, which job titles can create it, and status.',
        overviewAr: 'أنواع طلبات الخدمة تعرض كل نوع طلب مع الفئة والنوع الفرعي والمسميات المسموح لها.',
        affects: 'Which request types appear in the field app for each title.',
        before: [],
        steps: [
            {
                text: 'Open Service Request Types.',
                detail: 'The Add type form is at the top; the list of types (name, category, titles, status, Edit) is below.',
                shot: '30-service-request-types.jpg'
            },
            { text: 'Enter name, category and subtype, or click Edit on an existing type.' },
            { text: 'Choose the job titles allowed to create it and tick Active.' },
            { text: 'Click Save type.' },
            { text: 'Check the type appears for that title in the field app.' }
        ],
        tips: ['Request types are also switched on as a group in Field App Manager > Requests.'],
        cautions: ['"Load Marketing and Medical services" is a one-off seed; clicking again can create duplicates.'],
        related: ['field-app-manager']
    },
    'integrations-management': {
        overview:
            'Integrations Management is a status page for external connectors: IQVIA IMS, OneKey, Maps (Google Places and OpenStreetMap) and Mendix. It explains each status in plain words.',
        overviewAr: 'إدارة التكاملات صفحة حالة للموصلات الخارجية: IMS وOneKey والخرائط ومنديكس.',
        affects: 'Nothing; it is read-only.',
        before: [],
        steps: [
            {
                text: 'Open Integrations Management.',
                detail: 'Each connector shows Connected, Not connected, Not configured or Pending Setup with a short explanation.',
                shot: '31-integrations.jpg'
            },
            { text: 'Read the explanation under each status.' },
            { text: 'Open the linked admin module if one is offered.' },
            { text: 'Change credentials only with IT.' }
        ],
        tips: ['Not connected means not set up yet; it is not an error.'],
        cautions: [],
        related: ['bricks-management', 'chrome-data-tools']
    },
    'chrome-data-tools': {
        overview: 'Chrome and Data Tools is a reference page: recommended Chrome extensions for admins and ready-to-copy SOQL recipes for checking accounts, users, territories and ratings.',
        overviewAr: 'إضافات كروم وأدوات البيانات صفحة مرجعية: إضافات كروم ووصفات SOQL جاهزة.',
        affects: 'Nothing; it is reference only.',
        before: [],
        steps: [
            {
                text: 'Open Chrome and Data Tools.',
                detail: 'The top lists Chrome extensions (Salesforce Inspector Reloaded, Inspector classic, Data Loader) with store links. Below are SOQL recipes with a copy button.',
                shot: '32-chrome-data-tools.jpg'
            },
            { text: 'Install the extension you need from its link.' },
            { text: 'Copy a recipe and run it in Inspector.' },
            { text: 'Read the DML notes before any insert, update, upsert or delete.' }
        ],
        tips: ['Use these tools to read and check data. Run bulk changes in a sandbox first.'],
        cautions: [],
        related: ['integrations-management']
    }
};
