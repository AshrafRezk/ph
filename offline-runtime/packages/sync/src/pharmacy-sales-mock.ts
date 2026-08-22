/** Mock pharmacy sell-out data for offline dev / prime sessions. */

export interface PharmacySalesOptionDto {
  value: string;
  label: string;
}

export interface PharmacySalesFilterOptionsDto {
  therapyAreas: PharmacySalesOptionDto[];
  productFamilies: PharmacySalesOptionDto[];
  bricks: PharmacySalesOptionDto[];
  pharmacies: PharmacySalesOptionDto[];
  dataSources: PharmacySalesOptionDto[];
}

export interface PharmacySalesDetailRowDto {
  recordId: string;
  monthKey: string;
  monthLabel: string;
  pharmacyName: string;
  pharmacyId: string;
  brickName: string;
  brickId: string;
  productId: string;
  productName: string;
  productFamily: string;
  therapyArea: string;
  dataSource: string;
  quantity: number;
  unitPrice: number;
  revenue: number;
  visitCountWithDetailing?: number;
  commuteCostEstimate?: number;
  roiPercent?: number;
}

export interface PharmacySalesCachePayload {
  filterOptions: PharmacySalesFilterOptionsDto;
  detailRows: PharmacySalesDetailRowDto[];
}

const ALL = { value: 'All', label: 'All' };

function monthKey(offset: number): string {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() - offset);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

function monthLabel(key: string): string {
  const [y, m] = key.split('-').map(Number);
  const d = new Date(y, m - 1, 1);
  return d.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
}

export function buildPharmacySalesMockPayload(): PharmacySalesCachePayload {
  const bricks = [
    { id: 'brick-maadi', name: 'Maadi' },
    { id: 'brick-heliopolis', name: 'Heliopolis' },
    { id: 'brick-6oct', name: '6th October' }
  ];
  const pharmacies = [
    { id: 'pharm-001', name: 'El Ezaby Maadi', brickId: 'brick-maadi' },
    { id: 'pharm-002', name: 'Seif Pharmacies Heliopolis', brickId: 'brick-heliopolis' },
    { id: 'pharm-003', name: '19011 Pharmacy 6th Oct', brickId: 'brick-6oct' },
    { id: 'pharm-004', name: 'Maadi Central Pharmacy', brickId: 'brick-maadi' }
  ];
  const products = [
    {
      id: 'prod-empa',
      name: 'Empacoza 10mg',
      family: 'Empacoza',
      therapy: 'Cardiology',
      price: 285
    },
    {
      id: 'prod-empa25',
      name: 'Empacoza 25mg',
      family: 'Empacoza',
      therapy: 'Cardiology',
      price: 420
    },
    {
      id: 'prod-glu',
      name: 'Glucozen XR',
      family: 'Glucozen',
      therapy: 'Diabetes',
      price: 195
    },
    {
      id: 'prod-respi',
      name: 'RespiClear Inhaler',
      family: 'RespiClear',
      therapy: 'Respiratory',
      price: 340
    }
  ];

  const sources = ['IbnSina', 'Pharmaoverseas'] as const;
  const detailRows: PharmacySalesDetailRowDto[] = [];
  let seq = 1;

  for (let monthOffset = 0; monthOffset < 6; monthOffset++) {
    const key = monthKey(monthOffset);
    const label = monthLabel(key);
    for (const pharm of pharmacies) {
      const brick = bricks.find((b) => b.id === pharm.brickId)!;
      for (const product of products) {
        const qty = 12 + ((seq * 7 + monthOffset * 3) % 48);
        const source = sources[seq % 2];
        const revenue = qty * product.price;
        detailRows.push({
          recordId: `psw-${String(seq).padStart(4, '0')}`,
          monthKey: key,
          monthLabel: label,
          pharmacyName: pharm.name,
          pharmacyId: pharm.id,
          brickName: brick.name,
          brickId: brick.id,
          productId: product.id,
          productName: product.name,
          productFamily: product.family,
          therapyArea: product.therapy,
          dataSource: source,
          quantity: qty,
          unitPrice: product.price,
          revenue,
          visitCountWithDetailing: 2 + (seq % 4),
          commuteCostEstimate: 180 + (seq % 3) * 40,
          roiPercent: 8 + (seq % 17) - 4
        });
        seq++;
      }
    }
  }

  return {
    filterOptions: {
      therapyAreas: [
        ALL,
        { value: 'Cardiology', label: 'Cardiology' },
        { value: 'Diabetes', label: 'Diabetes' },
        { value: 'Respiratory', label: 'Respiratory' }
      ],
      productFamilies: [
        ALL,
        { value: 'Empacoza', label: 'Empacoza' },
        { value: 'Glucozen', label: 'Glucozen' },
        { value: 'RespiClear', label: 'RespiClear' }
      ],
      bricks: [ALL, ...bricks.map((b) => ({ value: b.id, label: b.name }))],
      pharmacies: [ALL, ...pharmacies.map((p) => ({ value: p.id, label: p.name }))],
      dataSources: [
        ALL,
        { value: 'IbnSina', label: 'IbnSina' },
        { value: 'Pharmaoverseas', label: 'Pharmaoverseas' }
      ]
    },
    detailRows
  };
}

export function buildPharmacySalesInsightsMockPayload(): {
  sessionId: string;
  headline: string;
  marketSummary: string;
  brandSummary: string;
  planSummary: string;
  marketTrends: {
    id: string;
    title: string;
    metric: string;
    direction: string;
    narrative: string;
  }[];
  brandTrends: {
    id: string;
    title: string;
    metric: string;
    direction: string;
    narrative: string;
  }[];
  recommendations: {
    recordId: string;
    recommendationType: string;
    title: string;
    description: string;
    status: string;
    targetUserName: string;
    sortOrder: number;
    selected: boolean;
  }[];
  vision: {
    visionSummary: string;
    focusTherapyAreas: string;
    focusProductFamilies: string;
  };
} {
  return {
    sessionId: 'offline-insight-session',
    headline: 'Maadi brick up 18% on Empacoza — prioritize affiliated cardiologists',
    marketSummary:
      'Sell-out in Maadi and Heliopolis outpaced territory average this cycle. IbnSina sourced withdrawals drove most of the uplift.',
    brandSummary:
      'Empacoza family leads revenue mix at 42% share. Glucozen XR steady; RespiClear soft in 6th October brick.',
    planSummary:
      'Three reps are below plan target on Class A pharmacy coverage. Recommend visit creation on affiliated HCP accounts.',
    marketTrends: [
      {
        id: 'm1',
        title: 'Maadi brick revenue',
        metric: '+18%',
        direction: 'up',
        narrative: 'Empacoza 10mg and pharmacy breadth drove Maadi above the 6-month baseline.'
      },
      {
        id: 'm2',
        title: 'Heliopolis unit volume',
        metric: '+9%',
        direction: 'up',
        narrative: 'Pharmaoverseas source rows increased; two pharmacies newly active in range.'
      },
      {
        id: 'm3',
        title: '6th October brick',
        metric: '-4%',
        direction: 'down',
        narrative: 'RespiClear inhaler withdrawals declined vs prior quarter — check stock-outs.'
      }
    ],
    brandTrends: [
      {
        id: 'b1',
        title: 'Empacoza family',
        metric: '+22%',
        direction: 'up',
        narrative: 'Strong cardiology pull-through; align rep visits with top pharmacy affiliates.'
      },
      {
        id: 'b2',
        title: 'Glucozen XR',
        metric: '+6%',
        direction: 'up',
        narrative: 'Stable diabetes sell-out; maintain current call frequency on Class A pharmacies.'
      },
      {
        id: 'b3',
        title: 'RespiClear',
        metric: '-11%',
        direction: 'down',
        narrative: 'Respiratory seasonality plus lower withdrawal counts in western bricks.'
      }
    ],
    recommendations: [
      {
        recordId: 'rec-001',
        recommendationType: 'CreateVisit',
        title: 'Create visit — Dr. Nabil Hassan (Cardiology)',
        description:
          'Affiliated with El Ezaby Maadi where Empacoza withdrawals rose 22%. Schedule detailing visit.',
        status: 'Proposed',
        targetUserName: 'Field Rep',
        sortOrder: 1,
        selected: true
      },
      {
        recordId: 'rec-002',
        recommendationType: 'UpdatePlanTarget',
        title: 'Raise Maadi brick plan target +8%',
        description: 'Sell-out trend supports higher cycle target for Maadi coverage reps.',
        status: 'Proposed',
        targetUserName: 'District Manager',
        sortOrder: 2,
        selected: true
      },
      {
        recordId: 'rec-003',
        recommendationType: 'EnsurePlan',
        title: 'Ensure Q3 plan exists for Heliopolis team',
        description: 'One rep has no active plan cycle aligned to Heliopolis brick pharmacies.',
        status: 'Proposed',
        targetUserName: 'Region Manager',
        sortOrder: 3,
        selected: false
      }
    ],
    vision: {
      visionSummary: 'Grow cardiology share in Greater Cairo through pharmacy-led pull-through.',
      focusTherapyAreas: 'Cardiology, Diabetes',
      focusProductFamilies: 'Empacoza, Glucozen'
    }
  };
}
