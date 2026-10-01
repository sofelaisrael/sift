import 'recall_harness.dart';

/// A deterministic synthetic corpus for proving the recall harness runs.
///
/// **These numbers are not a baseline.** Every record here was written by hand
/// to exercise a shape the real library has — dense OCR, labels only, no text
/// at all, CJK, hyphenated and underscored file names, repeated words, tags
/// only — and the recall that comes out describes this list, not the user's
/// screenshots. The real corpus does not exist yet; see [RecallCorpus].
///
/// Why synthetic at all: the harness has to be demonstrably functional before
/// there is anything to demonstrate it on, and a measurement tool that cannot
/// run until a data export exists is a measurement tool that does not get
/// written. The fixture is the smoke test; the baseline is the real run.
///
/// The list is `const` and free of clock or RNG input so two runs produce the
/// same corpus and therefore the same `corpusHash` in the report.
const List<RecallCorpusRecord> recallFixtureCorpus = [
  // ── Receipts ─────────────────────────────────────────────────────────────
  // The densest OCR in the corpus, and the shape that exposes the real defect
  // under measurement: `summary` (weight 5) is a slice of `ocrText` (weight 1),
  // so a word on the first line is scored twice from the same characters.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260112_084512.png',
    ocrText: 'Blue Bottle Coffee\nOat flat white 4.75\nCard ending 4417',
    objects: ['Receipt', 'Food'],
  ),
  RecallCorpusRecord(
    fileName: 'receipt_0417.png',
    ocrText: 'Pita Pit\nFalafel wrap 6.50\nTotal 6.50',
    objects: ['Receipt', 'Food'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260118_112233.png',
    ocrText: 'Zara\nSilk blouse 39.99\nTotal 39.99',
    objects: ['Receipt', 'Shopping', 'Clothing'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260119_093001.png',
    ocrText: 'Mercado do Lavrador\nTomatoes 2.10\nTotal 2.10 EUR',
    objects: ['Receipt', 'Food', 'Market'],
  ),
  RecallCorpusRecord(
    fileName: 'receipt_0088.png',
    ocrText: 'Pharmacie Centrale\nIbuprofen 3.20\nTotal 3.20',
    objects: ['Receipt', 'Medicine'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260121_171500.png',
    ocrText: 'Kopeckaya\nSourdough loaf 4.30\nTotal 4.30',
    objects: ['Receipt', 'Food'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260122_120745.png',
    ocrText: 'Cinema City\nAdult ticket 11.00\nSeat F12',
    objects: ['Ticket', 'Movie'],
  ),
  RecallCorpusRecord(
    fileName: 'receipt_1290.png',
    ocrText: 'Gymnasium Nord\nMonthly membership 39.00\nCard ending 4417',
    objects: ['Receipt', 'Fitness'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260124_201100.png',
    ocrText: 'Shell\nUnleaded 47.20\nTotal 47.20',
    objects: ['Car', 'Gas'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260125_074500.png',
    ocrText: 'Waffle Cartier\nLiege waffle 5.10\nTotal 5.10',
    objects: ['Dessert', 'Food'],
  ),
  // Latin script with a CJK word glued to it: two tokens, not one.
  RecallCorpusRecord(
    fileName: 'receipt_0031.png',
    ocrText: 'Konsum超市\nRice 2.15  Milk 1.40\nTotal 3.55',
    objects: ['Receipt', 'Market'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260127_133322.png',
    ocrText: 'Coop City\nInk cartridge 24.90\nTotal 24.90',
    objects: ['Receipt', 'Electronics'],
  ),

  // ── Chat and messages ────────────────────────────────────────────────────
  RecallCorpusRecord(
    fileName: 'Screenshot_20260105_214500.png',
    ocrText: 'Maria: are we still on for tomorrow\nAlex: yes 7pm',
    objects: ['Text', 'Chat'],
  ),
  RecallCorpusRecord(
    fileName: 'chat_0042.png',
    ocrText: 'Dad: the boiler is broken again\nMe: I will call the plumber',
    objects: ['Text', 'Chat'],
  ),
  // 'Document' is an ML Kit label here, and `document` is also the constant
  // `lamType`. The label is indexed, the type is not, and the harness must not
  // probe either spelling on this record.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260106_081500.png',
    ocrText: 'Dr. Almeida: your results are ready\nPortal ref LX-99120',
    objects: ['Text', 'Document'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260107_191000.png',
    ocrText:
        'Group trip\nAna: flight to Porto booked\nBo: I need a seat by the window',
    objects: ['Text', 'Chat', 'Travel'],
  ),
  RecallCorpusRecord(
    fileName: 'chat_0117.png',
    ocrText:
        'Work\nAna: standup moved to 9:30\nSam: I will bring the zeppelin metrics',
    objects: ['Text', 'Chat', 'Work'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260109_225500.png',
    ocrText: 'Mom: happy birthday\nLove you',
    objects: ['Text', 'Chat'],
  ),
  RecallCorpusRecord(
    fileName: 'chat_0203.png',
    ocrText: 'Bank\nYour transfer of 250.00 to Marco Silva is pending',
    objects: ['Text', 'Finance'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260111_100500.png',
    ocrText: 'Group run\n5k in 24:10\nPace 4:50',
    objects: ['Text', 'Fitness'],
  ),

  // ── Labels only, no readable text ────────────────────────────────────────
  // The shape Phase 2's gate is about: a screenshot whose only searchable
  // content is `objects` at weight 2.
  RecallCorpusRecord(
    fileName: 'skyline_sunset.png',
    objects: ['Skyline', 'Sunset', 'City'],
  ),
  RecallCorpusRecord(
    fileName: 'puppy_grass.png',
    objects: ['Dog', 'Puppy', 'Grass'],
  ),
  RecallCorpusRecord(
    fileName: 'plate_pasta.png',
    objects: ['Food', 'Pasta', 'Plate'],
  ),
  RecallCorpusRecord(
    fileName: 'furniture_ikea.png',
    objects: ['Furniture', 'Living room'],
  ),
  // 'Dog' is shared with puppy_grass, so its probe has two owners and only one
  // of them can be rank 1. The harness reports those separately instead of
  // quietly crediting whichever one the sort happened to put first.
  RecallCorpusRecord(
    fileName: 'dog_beach.png',
    objects: ['Dog', 'Beach'],
  ),
  RecallCorpusRecord(
    fileName: 'cat_white.png',
    objects: ['Cat', 'Animal'],
  ),
  RecallCorpusRecord(
    fileName: 'mountains_hike.png',
    objects: ['Mountain', 'Hiking', 'Sky'],
  ),
  RecallCorpusRecord(
    fileName: 'bicycle_city.png',
    objects: ['Bicycle', 'Bicycle helmet'],
  ),

  // ── No text and no labels ────────────────────────────────────────────────
  // The stored summary is the 'No text found' placeholder, which is display-only
  // and reaches the index nowhere. Nothing here is probeable, which is the
  // honest result: these records are only findable by file name.
  RecallCorpusRecord(fileName: 'Screenshot_20260115_140000.png'),
  RecallCorpusRecord(fileName: 'Screenshot_20260115_140100.png'),
  RecallCorpusRecord(fileName: 'Screenshot_20260115_140200.png'),
  RecallCorpusRecord(fileName: 'Screenshot_20260115_140300.png'),

  // ── CJK ──────────────────────────────────────────────────────────────────
  // A CJK run is one token, so a whole phrase is only reachable as a prefix.
  // '咖啡' alone is a legal 2-char query that is a prefix of '咖啡店的菜单'.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260103_101010.png',
    ocrText: '咖啡店的菜单\n拿铁 4.50  美式 3.80',
    objects: ['Receipt'],
  ),
  // A CJK run followed by digits: the run and the number are separate tokens.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260104_111111.png',
    ocrText: '订单编号 88341\n配送到 302 号',
    objects: ['Text', 'Document'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260105_121212.png',
    ocrText: '電車の時刻表\n新宿 09:14  渋谷 09:41',
    objects: ['Text', 'Travel'],
  ),
  // Brackets are separators, so the title is a bare CJK run.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260106_131313.png',
    ocrText: '图书馆借阅凭证\n《百年孤独》 归还日期 3 月 2 日',
    objects: ['Text', 'Book'],
  ),

  // ── Tags only, no text and no labels ─────────────────────────────────────
  // The user is the only source of content here, at weight 3.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260128_120000.png',
    tags: ['taxes', 'q1'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260128_120100.png',
    tags: ['taxes', 'q1'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260128_120200.png',
    tags: ['renewal', 'passport'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260128_120300.png',
    tags: ['renewal', 'visa'],
  ),
  // 'receipts' appears in well over the discriminativeness cutoff, so it must
  // be dropped as a probe even though it is the most deliberate query here.
  RecallCorpusRecord(
    fileName: 'Screenshot_20260128_120400.png',
    tags: ['receipts'],
  ),

  // ── Events and tickets ───────────────────────────────────────────────────
  RecallCorpusRecord(
    fileName: 'Screenshot_20260201_103000.png',
    ocrText: 'Rideline Cycles\nBike service booked\nRear derailleur 45.00',
    objects: ['Receipt', 'Bicycle', 'Repair'],
  ),
  RecallCorpusRecord(
    fileName: 'concert_ticket.png',
    ocrText: 'Adele Live\nRow G Seat 14\nDoors 19:00',
    objects: ['Ticket', 'Concert', 'Music'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260202_090000.png',
    ocrText: 'Flight LH1043\nSeat 23A\nGate B12 14:20',
    objects: ['Ticket', 'Travel', 'Airplane'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260203_110000.png',
    ocrText: 'Odeon Classics\nBeethoven Ninth\nHall 2 Row J',
    objects: ['Event', 'Music'],
  ),

  // ── Articles and notes ───────────────────────────────────────────────────
  RecallCorpusRecord(
    fileName: 'screenshot_0431.png',
    ocrText: 'How to prune a hydrangea\nCut the old wood above a pair of buds',
    objects: ['Text', 'Plant', 'Garden'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260205_190000.png',
    ocrText: 'Quarterly deck\nRevenue up 12%\nChurn down 3 points',
    objects: ['Text', 'Presentation', 'Business'],
  ),
  RecallCorpusRecord(
    fileName: 'article_0122.png',
    ocrText: 'Wagtail 6.4 released\nLong term support until 2028',
    objects: ['Text', 'Software'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260207_160000.png',
    ocrText: 'Dune Part Two\nRuntime 2h46m\nIMAX 70mm',
    objects: ['Movie', 'Text'],
  ),

  // ── File names that stress the splitter ──────────────────────────────────
  // Underscore and hyphen in one name. Dart's `\w` includes `_`, so a glued
  // token would make this file unreachable by any part of the name; the
  // filename is indexed at weight 1 and is the only field these two have.
  RecallCorpusRecord(
    fileName: 'under_score-name_2026-02-08.png',
    ocrText: 'Ridgeline permit\nBackcountry permit issued',
    objects: ['Document', 'Mountain'],
  ),
  RecallCorpusRecord(
    fileName: 'Screenshot_20260209_080000_edited.png',
    ocrText: 'Ferry timetable\nIbiza 07:45',
    objects: ['Text', 'Travel'],
  ),

  // ── Repetition inside one field ──────────────────────────────────────────
  // `zanzibar` is said four times in `zanzibar_quieter.png` and once in
  // `zanzibar_louder.png`, where it is also on the first line and so lands in
  // `summary` too. Counting occurrences per field would rank the quiet record
  // first; adding a weight once per field ranks the loud one 5 + 1 to 1. The
  // harness must reproduce that ordering without asserting it is desirable.
  RecallCorpusRecord(
    fileName: 'zanzibar_louder.png',
    ocrText: 'Zanzibar\nzanzibar zanzibar zanzibar zanzibar',
    objects: ['Food', 'Spice'],
  ),
  RecallCorpusRecord(
    fileName: 'zanzibar_quieter.png',
    ocrText: 'Zanzibar\nsumac sumac sumac',
    objects: ['Food', 'Spice'],
  ),
];
