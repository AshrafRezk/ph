/**
 * Export / import for Promo Grid Management.
 * Workbook layout is owned by c/promoGridWorkbook; this class loads org data,
 * validates import rows, and applies replace-per-section writes.
 */
public with sharing class PromoGridTransferService {
    private static final List<String> CLASS_CODES = new List<String>{
        'A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'
    };

    public class ExportPayload {
        @AuraEnabled public List<ExportLine> lines;
        @AuraEnabled public List<String> specialtyLabels;
        @AuraEnabled public List<String> classCodes;
        @AuraEnabled public Boolean includeValues;
    }

    public class ExportLine {
        @AuraEnabled public String lineName;
        @AuraEnabled public Id lineTerritoryId;
        @AuraEnabled public List<ExportProductRow> products;
        @AuraEnabled public List<ExportSpecialtyRow> specialties;
        @AuraEnabled public List<ExportClassRow> classes;
    }

    public class ExportProductRow {
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal weightPercentage;
    }

    public class ExportSpecialtyRow {
        @AuraEnabled public String specialty;
        @AuraEnabled public String specialtyLabel;
        @AuraEnabled public Decimal listPercentage;
    }

    public class ExportClassRow {
        @AuraEnabled public String classCode;
        @AuraEnabled public Decimal listPercentage;
        @AuraEnabled public Decimal targetMonthlyVisits;
    }

    public class ImportProductRow {
        @AuraEnabled public Integer excelRow;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal weightPercentage;
    }

    public class ImportSpecialtyRow {
        @AuraEnabled public Integer excelRow;
        @AuraEnabled public String specialty;
        @AuraEnabled public Decimal listPercentage;
    }

    public class ImportClassRow {
        @AuraEnabled public Integer excelRow;
        @AuraEnabled public String classCode;
        @AuraEnabled public Decimal listPercentage;
        @AuraEnabled public Decimal targetMonthlyVisits;
    }

    public class ImportLine {
        @AuraEnabled public String lineName;
        @AuraEnabled public List<ImportProductRow> products;
        @AuraEnabled public List<ImportSpecialtyRow> specialties;
        @AuraEnabled public List<ImportClassRow> classes;
    }

    public class SectionPlan {
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Integer added;
        @AuraEnabled public Integer updated;
        @AuraEnabled public Integer removed;
    }

    public class LinePlan {
        @AuraEnabled public String lineName;
        @AuraEnabled public Id lineTerritoryId;
        @AuraEnabled public String status;
        @AuraEnabled public SectionPlan products;
        @AuraEnabled public SectionPlan specialties;
        @AuraEnabled public SectionPlan classes;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> warnings;
    }

    public class ImportResult {
        @AuraEnabled public Integer readyCount;
        @AuraEnabled public Integer warningCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public Integer appliedCount;
        @AuraEnabled public List<LinePlan> lines;
        @AuraEnabled public List<String> messages;
    }

    private class ResolvedProduct {
        Id productId;
        Decimal weightPercentage;
        Integer excelRow;
    }

    private class ResolvedSpecialty {
        String specialty;
        Decimal listPercentage;
        Integer excelRow;
    }

    private class ResolvedClass {
        String classCode;
        Decimal listPercentage;
        Decimal targetMonthlyVisits;
        Integer excelRow;
    }

    private class LineWork {
        LinePlan plan;
        String territoryKey;
        List<ResolvedProduct> products = new List<ResolvedProduct>();
        List<ResolvedSpecialty> specialties = new List<ResolvedSpecialty>();
        List<ResolvedClass> classes = new List<ResolvedClass>();
        Boolean productsActive = false;
        Boolean specialtiesActive = false;
        Boolean classesActive = false;
    }

    @AuraEnabled(cacheable=false)
    public static ExportPayload getPromoGridExport(Boolean includeValues) {
        ExportPayload payload = new ExportPayload();
        payload.includeValues = includeValues == true;
        payload.classCodes = new List<String>(CLASS_CODES);
        payload.specialtyLabels = new List<String>();
        payload.lines = new List<ExportLine>();

        Map<String, String> specialtyLabels = PromoGridAdminController.picklistLabelMap(
            Promo_Grid_Specialty_Focus__c.Specialty__c.getDescribe()
        );
        for (PromoGridAdminController.PicklistOption option : PromoGridAdminController.toPicklistOptions(
            Promo_Grid_Specialty_Focus__c.Specialty__c.getDescribe()
        )) {
            payload.specialtyLabels.add(option.label);
        }

        List<Territory2> lineTerritories = loadLineTerritories();
        if (lineTerritories.isEmpty()) {
            return payload;
        }

        Map<Id, List<Product2>> productsByLine = bucketProductsByLine(lineTerritories);
        Map<String, Map<Id, Promo_Grid_Product_Weight__c>> weightsByLine = new Map<String, Map<Id, Promo_Grid_Product_Weight__c>>();
        Map<String, List<Promo_Grid_Specialty_Focus__c>> specialtiesByLine = new Map<String, List<Promo_Grid_Specialty_Focus__c>>();
        Map<String, Map<String, Promo_Grid_Class_Targeting__c>> classesByLine = new Map<String, Map<String, Promo_Grid_Class_Targeting__c>>();

        if (payload.includeValues) {
            Set<String> lineKeys = new Set<String>();
            for (Territory2 line : lineTerritories) {
                lineKeys.add(String.valueOf(line.Id));
            }
            weightsByLine = loadWeightsByLine(lineKeys);
            specialtiesByLine = loadSpecialtiesByLine(lineKeys);
            classesByLine = loadClassesByLine(lineKeys);
        }

        for (Territory2 line : lineTerritories) {
            ExportLine exportLine = new ExportLine();
            exportLine.lineName = line.Name;
            exportLine.lineTerritoryId = line.Id;
            exportLine.products = new List<ExportProductRow>();
            exportLine.specialties = new List<ExportSpecialtyRow>();
            exportLine.classes = new List<ExportClassRow>();

            String territoryKey = String.valueOf(line.Id);
            Map<Id, Promo_Grid_Product_Weight__c> weightByProduct = weightsByLine.containsKey(territoryKey)
                ? weightsByLine.get(territoryKey)
                : new Map<Id, Promo_Grid_Product_Weight__c>();

            List<Product2> lineProducts = productsByLine.containsKey(line.Id)
                ? productsByLine.get(line.Id)
                : new List<Product2>();
            Set<Id> productIdsSeen = new Set<Id>();
            for (Product2 product : lineProducts) {
                ExportProductRow row = new ExportProductRow();
                row.productCode = product.ProductCode;
                row.productName = product.Name;
                if (payload.includeValues && weightByProduct.containsKey(product.Id)) {
                    row.weightPercentage = PromoGridAdminController.displayPercent(
                        weightByProduct.get(product.Id).Weight_Percentage__c
                    );
                }
                exportLine.products.add(row);
                productIdsSeen.add(product.Id);
            }
            if (payload.includeValues) {
                for (Id productId : weightByProduct.keySet()) {
                    if (productIdsSeen.contains(productId)) {
                        continue;
                    }
                    Promo_Grid_Product_Weight__c weight = weightByProduct.get(productId);
                    ExportProductRow row = new ExportProductRow();
                    row.productCode = weight.Product2__r != null ? weight.Product2__r.ProductCode : null;
                    row.productName = weight.Product2__r != null ? weight.Product2__r.Name : null;
                    row.weightPercentage = PromoGridAdminController.displayPercent(weight.Weight_Percentage__c);
                    exportLine.products.add(row);
                }
            }

            if (payload.includeValues && specialtiesByLine.containsKey(territoryKey)) {
                for (Promo_Grid_Specialty_Focus__c specialty : specialtiesByLine.get(territoryKey)) {
                    ExportSpecialtyRow row = new ExportSpecialtyRow();
                    row.specialty = specialty.Specialty__c;
                    row.specialtyLabel = specialtyLabels.containsKey(specialty.Specialty__c)
                        ? specialtyLabels.get(specialty.Specialty__c)
                        : specialty.Specialty__c;
                    row.listPercentage = PromoGridAdminController.displayPercent(specialty.List_Percentage__c);
                    exportLine.specialties.add(row);
                }
            }

            Map<String, Promo_Grid_Class_Targeting__c> classByCode = classesByLine.containsKey(territoryKey)
                ? classesByLine.get(territoryKey)
                : new Map<String, Promo_Grid_Class_Targeting__c>();
            for (String classCode : CLASS_CODES) {
                ExportClassRow row = new ExportClassRow();
                row.classCode = classCode;
                if (payload.includeValues && classByCode.containsKey(classCode)) {
                    Promo_Grid_Class_Targeting__c saved = classByCode.get(classCode);
                    row.listPercentage = PromoGridAdminController.displayPercent(saved.List_Percentage__c);
                    row.targetMonthlyVisits = saved.Target_Monthly_Visits__c;
                }
                exportLine.classes.add(row);
            }

            payload.lines.add(exportLine);
        }

        return payload;
    }

    @AuraEnabled
    public static ImportResult previewPromoGridImport(List<ImportLine> lines) {
        return buildImportResult(lines, false);
    }

    @AuraEnabled
    public static ImportResult applyPromoGridImport(List<ImportLine> lines) {
        return buildImportResult(lines, true);
    }

    // The LWC sends the parsed workbook as a JSON string: Aura's own conversion of
    // List<ImportLine> drops lineName on large nested payloads, so every line came back unnamed.
    @AuraEnabled
    public static ImportResult previewPromoGridImportJson(String linesJson) {
        return buildImportResult(parseImportLines(linesJson), false);
    }

    @AuraEnabled
    public static ImportResult applyPromoGridImportJson(String linesJson) {
        return buildImportResult(parseImportLines(linesJson), true);
    }

    private static List<ImportLine> parseImportLines(String linesJson) {
        if (String.isBlank(linesJson)) {
            return new List<ImportLine>();
        }
        return (List<ImportLine>) JSON.deserialize(linesJson, List<ImportLine>.class);
    }

    private static ImportResult buildImportResult(List<ImportLine> lines, Boolean applyChanges) {
        ImportResult result = new ImportResult();
        result.readyCount = 0;
        result.warningCount = 0;
        result.skippedCount = 0;
        result.appliedCount = 0;
        result.lines = new List<LinePlan>();
        result.messages = new List<String>();

        if (lines == null || lines.isEmpty()) {
            result.messages.add('No import rows were provided.');
            return result;
        }

        LineIndex lineIndex = buildLineIndex();
        ProductIndex productIndex = buildProductIndex();
        Map<String, String> specialtyByKey = buildSpecialtyIndex();
        Set<String> classCodes = new Set<String>();
        for (String classCode : CLASS_CODES) {
            classCodes.add(classCode.toUpperCase());
        }

        List<LineWork> works = new List<LineWork>();
        Set<Id> touchedLineIds = new Set<Id>();
        for (ImportLine importLine : lines) {
            LineWork work = planLine(importLine, lineIndex, productIndex, specialtyByKey, classCodes);
            works.add(work);
            result.lines.add(work.plan);
            if (work.plan.lineTerritoryId != null) {
                touchedLineIds.add(work.plan.lineTerritoryId);
            }
            if (work.plan.status == 'error') {
                result.skippedCount++;
            } else if (work.plan.status == 'warning') {
                result.warningCount++;
                result.readyCount++;
            } else if (work.plan.status == 'ready') {
                result.readyCount++;
            } else {
                result.skippedCount++;
            }
            if (work.plan.errors != null) {
                result.messages.addAll(work.plan.errors);
            }
            if (work.plan.warnings != null) {
                result.messages.addAll(work.plan.warnings);
            }
        }

        fillSectionCounts(works, touchedLineIds);

        if (applyChanges == true) {
            // A file with any error line is rejected as a whole: nothing is written until it is fixed.
            Integer errorLines = countErrorLines(works);
            if (errorLines > 0) {
                result.messages.add(0,
                    'Nothing was imported: fix the ' + errorLines + ' line' + (errorLines == 1 ? '' : 's')
                    + ' with errors and upload the file again.'
                );
                return result;
            }
            applyPlans(works, touchedLineIds);
            Integer applied = 0;
            for (LineWork work : works) {
                if (work.plan.status == 'ready' || work.plan.status == 'warning') {
                    applied++;
                }
            }
            result.appliedCount = applied;
        }

        return result;
    }

    private static Integer countErrorLines(List<LineWork> works) {
        Integer errorLines = 0;
        for (LineWork work : works) {
            if (work.plan.status == 'error') {
                errorLines++;
            }
        }
        return errorLines;
    }

    private static void fillSectionCounts(List<LineWork> works, Set<Id> touchedLineIds) {
        if (touchedLineIds == null || touchedLineIds.isEmpty()) {
            return;
        }
        Set<String> territoryKeys = new Set<String>();
        for (Id lineId : touchedLineIds) {
            territoryKeys.add(String.valueOf(lineId));
        }
        Map<String, Map<Id, Promo_Grid_Product_Weight__c>> existingWeights = loadWeightsByLine(territoryKeys);
        Map<String, Map<String, Promo_Grid_Specialty_Focus__c>> existingSpecialties = loadSpecialtyMapByLine(
            territoryKeys
        );
        Map<String, Map<String, Promo_Grid_Class_Targeting__c>> existingClasses = loadClassesByLine(territoryKeys);

        for (LineWork work : works) {
            if (work.plan.status != 'ready' && work.plan.status != 'warning') {
                continue;
            }
            String territoryKey = work.territoryKey;
            if (work.productsActive) {
                Map<Id, Promo_Grid_Product_Weight__c> existing = existingWeights.containsKey(territoryKey)
                    ? existingWeights.get(territoryKey)
                    : new Map<Id, Promo_Grid_Product_Weight__c>();
                Set<Id> keep = new Set<Id>();
                Integer added = 0;
                Integer updated = 0;
                for (ResolvedProduct resolved : work.products) {
                    keep.add(resolved.productId);
                    if (existing.containsKey(resolved.productId)) {
                        updated++;
                    } else {
                        added++;
                    }
                }
                Integer removed = 0;
                for (Id productId : existing.keySet()) {
                    if (!keep.contains(productId)) {
                        removed++;
                    }
                }
                work.plan.products.added = added;
                work.plan.products.updated = updated;
                work.plan.products.removed = removed;
            }
            if (work.specialtiesActive) {
                Map<String, Promo_Grid_Specialty_Focus__c> existing = existingSpecialties.containsKey(territoryKey)
                    ? existingSpecialties.get(territoryKey)
                    : new Map<String, Promo_Grid_Specialty_Focus__c>();
                Set<String> keep = new Set<String>();
                Integer added = 0;
                Integer updated = 0;
                for (ResolvedSpecialty resolved : work.specialties) {
                    keep.add(resolved.specialty);
                    if (existing.containsKey(resolved.specialty)) {
                        updated++;
                    } else {
                        added++;
                    }
                }
                Integer removed = 0;
                for (String specialty : existing.keySet()) {
                    if (!keep.contains(specialty)) {
                        removed++;
                    }
                }
                work.plan.specialties.added = added;
                work.plan.specialties.updated = updated;
                work.plan.specialties.removed = removed;
            }
            if (work.classesActive) {
                Map<String, Promo_Grid_Class_Targeting__c> existing = existingClasses.containsKey(territoryKey)
                    ? existingClasses.get(territoryKey)
                    : new Map<String, Promo_Grid_Class_Targeting__c>();
                Set<String> keep = new Set<String>();
                Integer added = 0;
                Integer updated = 0;
                for (ResolvedClass resolved : work.classes) {
                    keep.add(resolved.classCode);
                    if (existing.containsKey(resolved.classCode)) {
                        updated++;
                    } else {
                        added++;
                    }
                }
                Integer removed = 0;
                for (String classCode : existing.keySet()) {
                    if (!keep.contains(classCode)) {
                        removed++;
                    }
                }
                work.plan.classes.added = added;
                work.plan.classes.updated = updated;
                work.plan.classes.removed = removed;
            }
        }
    }

    private static LineWork planLine(
        ImportLine importLine,
        LineIndex lineIndex,
        ProductIndex productIndex,
        Map<String, String> specialtyByKey,
        Set<String> classCodes
    ) {
        LineWork work = new LineWork();
        work.plan = emptyLinePlan(importLine != null ? importLine.lineName : null);

        if (importLine == null || String.isBlank(importLine.lineName)) {
            work.plan.status = 'error';
            work.plan.errors.add('Line name is required.');
            return work;
        }

        String matchKey = normalizeKey(importLine.lineName);
        if (!lineIndex.byKey.containsKey(matchKey)) {
            work.plan.status = 'error';
            work.plan.errors.add('Unknown line "' + importLine.lineName + '".');
            return work;
        }
        List<Territory2> matches = lineIndex.byKey.get(matchKey);
        if (matches.size() > 1) {
            work.plan.status = 'error';
            work.plan.errors.add('Ambiguous line "' + importLine.lineName + '".');
            return work;
        }

        Territory2 line = matches[0];
        work.plan.lineName = line.Name;
        work.plan.lineTerritoryId = line.Id;
        work.territoryKey = String.valueOf(line.Id);

        resolveProducts(work, importLine.products, productIndex);
        resolveSpecialties(work, importLine.specialties, specialtyByKey);
        resolveClasses(work, importLine.classes, classCodes);

        if (!work.plan.errors.isEmpty()) {
            work.plan.status = 'error';
            return work;
        }

        if (!work.productsActive && !work.specialtiesActive && !work.classesActive) {
            work.plan.status = 'empty';
            return work;
        }

        if (!work.plan.warnings.isEmpty()) {
            work.plan.status = 'warning';
        } else {
            work.plan.status = 'ready';
        }
        return work;
    }

    private static void resolveProducts(
        LineWork work,
        List<ImportProductRow> rows,
        ProductIndex productIndex
    ) {
        SectionPlan section = emptySection();
        work.plan.products = section;
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Map<Id, ResolvedProduct> byProductId = new Map<Id, ResolvedProduct>();
        Decimal total = 0;
        Boolean anyPercent = false;
        for (ImportProductRow row : rows) {
            if (row == null) {
                continue;
            }
            if (row.weightPercentage == null) {
                continue;
            }
            anyPercent = true;
            Decimal percent = normalizePercent(row.weightPercentage);
            if (percent == null || percent < 0 || percent > 100) {
                work.plan.errors.add(
                    'Products row ' + row.excelRow + ': weight percentage must be between 0 and 100.'
                );
                continue;
            }

            Product2 product = resolveProduct(row, productIndex);
            if (product == null) {
                String productHint = String.isNotBlank(row.productCode)
                    ? 'product code ' + row.productCode
                    : 'product name ' + row.productName;
                work.plan.errors.add('Products row ' + row.excelRow + ': ' + productHint + ' not found.');
                continue;
            }
            if (byProductId.containsKey(product.Id)) {
                work.plan.errors.add(
                    'Products row ' + row.excelRow + ': duplicate product "' + product.Name + '" for this line.'
                );
                continue;
            }

            ResolvedProduct resolved = new ResolvedProduct();
            resolved.productId = product.Id;
            resolved.weightPercentage = percent;
            resolved.excelRow = row.excelRow;
            byProductId.put(product.Id, resolved);
            total += percent;
        }

        if (!anyPercent) {
            return;
        }
        work.productsActive = true;
        section.active = true;
        section.total = total;
        work.products = byProductId.values();
        if (total > 100.01) {
            work.plan.errors.add(
                'Products for ' + work.plan.lineName + ' total ' + total.setScale(1) + '% (over 100%).'
            );
        } else if (Math.abs(100 - total) >= 0.01) {
            work.plan.warnings.add(
                'Products for ' + work.plan.lineName + ' total ' + total.setScale(1) + '% (under 100%).'
            );
        }
    }

    private static void resolveSpecialties(
        LineWork work,
        List<ImportSpecialtyRow> rows,
        Map<String, String> specialtyByKey
    ) {
        SectionPlan section = emptySection();
        work.plan.specialties = section;
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Map<String, ResolvedSpecialty> bySpecialty = new Map<String, ResolvedSpecialty>();
        Decimal total = 0;
        Boolean anyPercent = false;
        for (ImportSpecialtyRow row : rows) {
            if (row == null || row.listPercentage == null) {
                continue;
            }
            anyPercent = true;
            Decimal percent = normalizePercent(row.listPercentage);
            if (percent == null || percent < 0 || percent > 100) {
                work.plan.errors.add(
                    'Specialties row ' + row.excelRow + ': list percentage must be between 0 and 100.'
                );
                continue;
            }
            if (String.isBlank(row.specialty)) {
                work.plan.errors.add('Specialties row ' + row.excelRow + ': specialty is required.');
                continue;
            }
            String specialtyValue = specialtyByKey.get(normalizeKey(row.specialty));
            if (specialtyValue == null) {
                work.plan.errors.add(
                    'Specialties row ' + row.excelRow + ': specialty "' + row.specialty + '" not found.'
                );
                continue;
            }
            if (bySpecialty.containsKey(specialtyValue)) {
                work.plan.errors.add(
                    'Specialties row ' + row.excelRow + ': duplicate specialty "' + row.specialty + '" for this line.'
                );
                continue;
            }
            ResolvedSpecialty resolved = new ResolvedSpecialty();
            resolved.specialty = specialtyValue;
            resolved.listPercentage = percent;
            resolved.excelRow = row.excelRow;
            bySpecialty.put(specialtyValue, resolved);
            total += percent;
        }

        if (!anyPercent) {
            return;
        }
        work.specialtiesActive = true;
        section.active = true;
        section.total = total;
        work.specialties = bySpecialty.values();
        if (total > 100.01) {
            work.plan.errors.add(
                'Specialties for ' + work.plan.lineName + ' total ' + total.setScale(1) + '% (over 100%).'
            );
        } else if (Math.abs(100 - total) >= 0.01) {
            work.plan.warnings.add(
                'Specialties for ' + work.plan.lineName + ' total ' + total.setScale(1) + '% (under 100%).'
            );
        }
    }

    private static void resolveClasses(
        LineWork work,
        List<ImportClassRow> rows,
        Set<String> classCodes
    ) {
        SectionPlan section = emptySection();
        work.plan.classes = section;
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Map<String, ResolvedClass> byClass = new Map<String, ResolvedClass>();
        Decimal total = 0;
        Boolean anyPercent = false;
        for (ImportClassRow row : rows) {
            if (row == null || row.listPercentage == null) {
                continue;
            }
            anyPercent = true;
            Decimal percent = normalizePercent(row.listPercentage);
            if (percent == null || percent < 0 || percent > 100) {
                work.plan.errors.add(
                    'Classes row ' + row.excelRow + ': list percentage must be between 0 and 100.'
                );
                continue;
            }
            if (String.isBlank(row.classCode)) {
                work.plan.errors.add('Classes row ' + row.excelRow + ': class is required.');
                continue;
            }
            String normalizedClass = row.classCode.trim().toUpperCase();
            if (!classCodes.contains(normalizedClass)) {
                work.plan.errors.add(
                    'Classes row ' + row.excelRow + ': class "' + row.classCode + '" is not valid (A1–C3).'
                );
                continue;
            }
            if (byClass.containsKey(normalizedClass)) {
                work.plan.errors.add(
                    'Classes row ' + row.excelRow + ': duplicate class "' + row.classCode + '" for this line.'
                );
                continue;
            }
            if (row.targetMonthlyVisits != null && row.targetMonthlyVisits < 0) {
                work.plan.errors.add(
                    'Classes row ' + row.excelRow + ': target monthly visits must be 0 or more.'
                );
                continue;
            }
            if (row.targetMonthlyVisits != null && row.targetMonthlyVisits != row.targetMonthlyVisits.setScale(0)) {
                work.plan.errors.add(
                    'Classes row ' + row.excelRow + ': target monthly visits must be a whole number.'
                );
                continue;
            }

            ResolvedClass resolved = new ResolvedClass();
            resolved.classCode = normalizedClass;
            resolved.listPercentage = percent;
            resolved.targetMonthlyVisits = row.targetMonthlyVisits;
            resolved.excelRow = row.excelRow;
            byClass.put(normalizedClass, resolved);
            total += percent;
        }

        if (!anyPercent) {
            return;
        }
        work.classesActive = true;
        section.active = true;
        section.total = total;
        work.classes = byClass.values();
        if (total > 100.01) {
            work.plan.errors.add(
                'Classes for ' + work.plan.lineName + ' total ' + total.setScale(1) + '% (over 100%).'
            );
        } else if (Math.abs(100 - total) >= 0.01) {
            work.plan.warnings.add(
                'Classes for ' + work.plan.lineName + ' total ' + total.setScale(1) + '% (under 100%).'
            );
        }
    }

    private static void applyPlans(List<LineWork> works, Set<Id> touchedLineIds) {
        if (touchedLineIds == null || touchedLineIds.isEmpty()) {
            return;
        }

        Set<String> territoryKeys = new Set<String>();
        for (Id lineId : touchedLineIds) {
            territoryKeys.add(String.valueOf(lineId));
        }

        Map<String, Map<Id, Promo_Grid_Product_Weight__c>> existingWeights = loadWeightsByLine(territoryKeys);
        Map<String, Map<String, Promo_Grid_Specialty_Focus__c>> existingSpecialties = loadSpecialtyMapByLine(
            territoryKeys
        );
        Map<String, Map<String, Promo_Grid_Class_Targeting__c>> existingClasses = loadClassesByLine(territoryKeys);

        List<Promo_Grid_Product_Weight__c> weightsToInsert = new List<Promo_Grid_Product_Weight__c>();
        List<Promo_Grid_Product_Weight__c> weightsToUpdate = new List<Promo_Grid_Product_Weight__c>();
        List<Promo_Grid_Product_Weight__c> weightsToDelete = new List<Promo_Grid_Product_Weight__c>();
        List<Promo_Grid_Specialty_Focus__c> specialtiesToInsert = new List<Promo_Grid_Specialty_Focus__c>();
        List<Promo_Grid_Specialty_Focus__c> specialtiesToUpdate = new List<Promo_Grid_Specialty_Focus__c>();
        List<Promo_Grid_Specialty_Focus__c> specialtiesToDelete = new List<Promo_Grid_Specialty_Focus__c>();
        List<Promo_Grid_Class_Targeting__c> classesToInsert = new List<Promo_Grid_Class_Targeting__c>();
        List<Promo_Grid_Class_Targeting__c> classesToUpdate = new List<Promo_Grid_Class_Targeting__c>();
        List<Promo_Grid_Class_Targeting__c> classesToDelete = new List<Promo_Grid_Class_Targeting__c>();

        for (LineWork work : works) {
            if (work.plan.status != 'ready' && work.plan.status != 'warning') {
                continue;
            }
            String territoryKey = work.territoryKey;

            if (work.productsActive) {
                Map<Id, Promo_Grid_Product_Weight__c> existing = existingWeights.containsKey(territoryKey)
                    ? existingWeights.get(territoryKey)
                    : new Map<Id, Promo_Grid_Product_Weight__c>();
                Set<Id> keep = new Set<Id>();
                Integer added = 0;
                Integer updated = 0;
                for (ResolvedProduct resolved : work.products) {
                    keep.add(resolved.productId);
                    if (existing.containsKey(resolved.productId)) {
                        Promo_Grid_Product_Weight__c record = existing.get(resolved.productId);
                        record.Weight_Percentage__c = resolved.weightPercentage;
                        record.Unique_Key__c = territoryKey + ':' + String.valueOf(resolved.productId);
                        weightsToUpdate.add(record);
                        updated++;
                    } else {
                        Promo_Grid_Product_Weight__c record = new Promo_Grid_Product_Weight__c();
                        record.Territory2_Id__c = territoryKey;
                        record.Product2__c = resolved.productId;
                        record.Weight_Percentage__c = resolved.weightPercentage;
                        record.Unique_Key__c = territoryKey + ':' + String.valueOf(resolved.productId);
                        weightsToInsert.add(record);
                        added++;
                    }
                }
                Integer removed = 0;
                for (Id productId : existing.keySet()) {
                    if (!keep.contains(productId)) {
                        weightsToDelete.add(existing.get(productId));
                        removed++;
                    }
                }
                work.plan.products.added = added;
                work.plan.products.updated = updated;
                work.plan.products.removed = removed;
            }

            if (work.specialtiesActive) {
                Map<String, Promo_Grid_Specialty_Focus__c> existing = existingSpecialties.containsKey(territoryKey)
                    ? existingSpecialties.get(territoryKey)
                    : new Map<String, Promo_Grid_Specialty_Focus__c>();
                Set<String> keep = new Set<String>();
                Integer added = 0;
                Integer updated = 0;
                for (ResolvedSpecialty resolved : work.specialties) {
                    keep.add(resolved.specialty);
                    if (existing.containsKey(resolved.specialty)) {
                        Promo_Grid_Specialty_Focus__c record = existing.get(resolved.specialty);
                        record.List_Percentage__c = resolved.listPercentage;
                        record.Unique_Key__c = PromoGridAdminController.buildSpecialtyKey(
                            territoryKey,
                            resolved.specialty
                        );
                        specialtiesToUpdate.add(record);
                        updated++;
                    } else {
                        Promo_Grid_Specialty_Focus__c record = new Promo_Grid_Specialty_Focus__c();
                        record.Territory2_Id__c = territoryKey;
                        record.Specialty__c = resolved.specialty;
                        record.List_Percentage__c = resolved.listPercentage;
                        record.Unique_Key__c = PromoGridAdminController.buildSpecialtyKey(
                            territoryKey,
                            resolved.specialty
                        );
                        specialtiesToInsert.add(record);
                        added++;
                    }
                }
                Integer removed = 0;
                for (String specialty : existing.keySet()) {
                    if (!keep.contains(specialty)) {
                        specialtiesToDelete.add(existing.get(specialty));
                        removed++;
                    }
                }
                work.plan.specialties.added = added;
                work.plan.specialties.updated = updated;
                work.plan.specialties.removed = removed;
            }

            if (work.classesActive) {
                Map<String, Promo_Grid_Class_Targeting__c> existing = existingClasses.containsKey(territoryKey)
                    ? existingClasses.get(territoryKey)
                    : new Map<String, Promo_Grid_Class_Targeting__c>();
                Set<String> keep = new Set<String>();
                Integer added = 0;
                Integer updated = 0;
                for (ResolvedClass resolved : work.classes) {
                    keep.add(resolved.classCode);
                    if (existing.containsKey(resolved.classCode)) {
                        Promo_Grid_Class_Targeting__c record = existing.get(resolved.classCode);
                        record.List_Percentage__c = resolved.listPercentage;
                        record.Target_Monthly_Visits__c = resolved.targetMonthlyVisits;
                        record.Unique_Key__c = territoryKey + ':' + resolved.classCode;
                        classesToUpdate.add(record);
                        updated++;
                    } else {
                        Promo_Grid_Class_Targeting__c record = new Promo_Grid_Class_Targeting__c();
                        record.Territory2_Id__c = territoryKey;
                        record.Class__c = resolved.classCode;
                        record.List_Percentage__c = resolved.listPercentage;
                        record.Target_Monthly_Visits__c = resolved.targetMonthlyVisits;
                        record.Unique_Key__c = territoryKey + ':' + resolved.classCode;
                        classesToInsert.add(record);
                        added++;
                    }
                }
                Integer removed = 0;
                for (String classCode : existing.keySet()) {
                    if (!keep.contains(classCode)) {
                        classesToDelete.add(existing.get(classCode));
                        removed++;
                    }
                }
                work.plan.classes.added = added;
                work.plan.classes.updated = updated;
                work.plan.classes.removed = removed;
            }
        }

        if (!weightsToDelete.isEmpty()) {
            delete as system weightsToDelete;
        }
        if (!specialtiesToDelete.isEmpty()) {
            delete as system specialtiesToDelete;
        }
        if (!classesToDelete.isEmpty()) {
            delete as system classesToDelete;
        }
        if (!weightsToInsert.isEmpty()) {
            insert as system weightsToInsert;
        }
        if (!weightsToUpdate.isEmpty()) {
            update as system weightsToUpdate;
        }
        if (!specialtiesToInsert.isEmpty()) {
            insert as system specialtiesToInsert;
        }
        if (!specialtiesToUpdate.isEmpty()) {
            update as system specialtiesToUpdate;
        }
        if (!classesToInsert.isEmpty()) {
            insert as system classesToInsert;
        }
        if (!classesToUpdate.isEmpty()) {
            update as system classesToUpdate;
        }
    }

    private static List<Territory2> loadLineTerritories() {
        List<Territory2> lines = new List<Territory2>();
        for (Territory2 territory : PromoGridAdminController.queryTerritoriesForTree()) {
            if (PromoGridAdminController.isLineTerritory(territory)) {
                lines.add(territory);
            }
        }
        lines.sort(new TerritoryNameComparator());
        return lines;
    }

    private static Map<Id, List<Product2>> bucketProductsByLine(List<Territory2> lineTerritories) {
        Map<Id, List<Product2>> productsByLine = new Map<Id, List<Product2>>();
        Map<String, List<Id>> lineIdsByKey = new Map<String, List<Id>>();
        for (Territory2 line : lineTerritories) {
            productsByLine.put(line.Id, new List<Product2>());
            for (String key : TerritoryManagementController.buildLineMatchKeysPublic(
                line.Name,
                (String) line.get('External_ID__c')
            )) {
                if (!lineIdsByKey.containsKey(key)) {
                    lineIdsByKey.put(key, new List<Id>());
                }
                lineIdsByKey.get(key).add(line.Id);
            }
        }

        for (Product2 product : [
            SELECT Id, Name, ProductCode, Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE
                IsActive = TRUE
                AND (
                    (Sales_Line__c != NULL AND Sales_Line__c != '')
                    OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
                )
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 10000
        ]) {
            Set<Id> matchedLineIds = new Set<Id>();
            addLineIdsForLabel(matchedLineIds, product.Sales_Line__c, lineIdsByKey);
            for (String mirrorLabel : splitMirrorLabels(product.Mirror_Line__c)) {
                addLineIdsForLabel(matchedLineIds, mirrorLabel, lineIdsByKey);
            }
            for (Id lineId : matchedLineIds) {
                productsByLine.get(lineId).add(product);
            }
        }
        return productsByLine;
    }

    private static void addLineIdsForLabel(
        Set<Id> matchedLineIds,
        String label,
        Map<String, List<Id>> lineIdsByKey
    ) {
        String key = normalizeKey(label);
        if (String.isBlank(key) || !lineIdsByKey.containsKey(key)) {
            return;
        }
        matchedLineIds.addAll(lineIdsByKey.get(key));
    }

    private static Map<String, Map<Id, Promo_Grid_Product_Weight__c>> loadWeightsByLine(Set<String> lineKeys) {
        Map<String, Map<Id, Promo_Grid_Product_Weight__c>> byLine = new Map<String, Map<Id, Promo_Grid_Product_Weight__c>>();
        if (lineKeys == null || lineKeys.isEmpty()) {
            return byLine;
        }
        for (Promo_Grid_Product_Weight__c record : [
            SELECT Id, Territory2_Id__c, Product2__c, Product2__r.Name, Product2__r.ProductCode, Weight_Percentage__c, Unique_Key__c
            FROM Promo_Grid_Product_Weight__c
            WHERE Territory2_Id__c IN :lineKeys
            WITH SYSTEM_MODE
        ]) {
            if (!byLine.containsKey(record.Territory2_Id__c)) {
                byLine.put(record.Territory2_Id__c, new Map<Id, Promo_Grid_Product_Weight__c>());
            }
            byLine.get(record.Territory2_Id__c).put(record.Product2__c, record);
        }
        return byLine;
    }

    private static Map<String, List<Promo_Grid_Specialty_Focus__c>> loadSpecialtiesByLine(Set<String> lineKeys) {
        Map<String, List<Promo_Grid_Specialty_Focus__c>> byLine = new Map<String, List<Promo_Grid_Specialty_Focus__c>>();
        if (lineKeys == null || lineKeys.isEmpty()) {
            return byLine;
        }
        for (Promo_Grid_Specialty_Focus__c record : [
            SELECT Id, Territory2_Id__c, Specialty__c, List_Percentage__c, Unique_Key__c
            FROM Promo_Grid_Specialty_Focus__c
            WHERE Territory2_Id__c IN :lineKeys
            WITH SYSTEM_MODE
            ORDER BY Specialty__c
        ]) {
            if (!byLine.containsKey(record.Territory2_Id__c)) {
                byLine.put(record.Territory2_Id__c, new List<Promo_Grid_Specialty_Focus__c>());
            }
            byLine.get(record.Territory2_Id__c).add(record);
        }
        return byLine;
    }

    private static Map<String, Map<String, Promo_Grid_Specialty_Focus__c>> loadSpecialtyMapByLine(
        Set<String> lineKeys
    ) {
        Map<String, Map<String, Promo_Grid_Specialty_Focus__c>> byLine = new Map<String, Map<String, Promo_Grid_Specialty_Focus__c>>();
        Map<String, List<Promo_Grid_Specialty_Focus__c>> lists = loadSpecialtiesByLine(lineKeys);
        for (String territoryKey : lists.keySet()) {
            Map<String, Promo_Grid_Specialty_Focus__c> bySpecialty = new Map<String, Promo_Grid_Specialty_Focus__c>();
            for (Promo_Grid_Specialty_Focus__c record : lists.get(territoryKey)) {
                bySpecialty.put(record.Specialty__c, record);
            }
            byLine.put(territoryKey, bySpecialty);
        }
        return byLine;
    }

    private static Map<String, Map<String, Promo_Grid_Class_Targeting__c>> loadClassesByLine(Set<String> lineKeys) {
        Map<String, Map<String, Promo_Grid_Class_Targeting__c>> byLine = new Map<String, Map<String, Promo_Grid_Class_Targeting__c>>();
        if (lineKeys == null || lineKeys.isEmpty()) {
            return byLine;
        }
        for (Promo_Grid_Class_Targeting__c record : [
            SELECT Id, Territory2_Id__c, Class__c, List_Percentage__c, Target_Monthly_Visits__c, Unique_Key__c
            FROM Promo_Grid_Class_Targeting__c
            WHERE Territory2_Id__c IN :lineKeys
            WITH SYSTEM_MODE
        ]) {
            if (!byLine.containsKey(record.Territory2_Id__c)) {
                byLine.put(record.Territory2_Id__c, new Map<String, Promo_Grid_Class_Targeting__c>());
            }
            byLine.get(record.Territory2_Id__c).put(record.Class__c, record);
        }
        return byLine;
    }

    private class LineIndex {
        Map<String, List<Territory2>> byKey = new Map<String, List<Territory2>>();
    }

    private class ProductIndex {
        Map<String, Product2> byCode = new Map<String, Product2>();
        Map<String, List<Product2>> byName = new Map<String, List<Product2>>();
    }

    private static LineIndex buildLineIndex() {
        LineIndex index = new LineIndex();
        for (Territory2 line : loadLineTerritories()) {
            for (String key : TerritoryManagementController.buildLineMatchKeysPublic(
                line.Name,
                (String) line.get('External_ID__c')
            )) {
                if (!index.byKey.containsKey(key)) {
                    index.byKey.put(key, new List<Territory2>());
                }
                index.byKey.get(key).add(line);
            }
            String nameKey = normalizeKey(line.Name);
            if (String.isNotBlank(nameKey) && !index.byKey.containsKey(nameKey)) {
                index.byKey.put(nameKey, new List<Territory2>{ line });
            }
        }
        return index;
    }

    private static ProductIndex buildProductIndex() {
        ProductIndex index = new ProductIndex();
        for (Product2 product : [
            SELECT Id, Name, ProductCode
            FROM Product2
            WHERE IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 10000
        ]) {
            if (String.isNotBlank(product.ProductCode)) {
                index.byCode.put(product.ProductCode.trim().toUpperCase(), product);
            }
            String nameKey = normalizeKey(product.Name);
            if (String.isNotBlank(nameKey)) {
                if (!index.byName.containsKey(nameKey)) {
                    index.byName.put(nameKey, new List<Product2>());
                }
                index.byName.get(nameKey).add(product);
            }
        }
        return index;
    }

    private static Map<String, String> buildSpecialtyIndex() {
        Map<String, String> byKey = new Map<String, String>();
        for (PromoGridAdminController.PicklistOption option : PromoGridAdminController.toPicklistOptions(
            Promo_Grid_Specialty_Focus__c.Specialty__c.getDescribe()
        )) {
            byKey.put(normalizeKey(option.value), option.value);
            byKey.put(normalizeKey(option.label), option.value);
        }
        return byKey;
    }

    private static Product2 resolveProduct(ImportProductRow row, ProductIndex productIndex) {
        if (String.isNotBlank(row.productCode)) {
            String codeKey = row.productCode.trim().toUpperCase();
            if (productIndex.byCode.containsKey(codeKey)) {
                return productIndex.byCode.get(codeKey);
            }
        }
        if (String.isNotBlank(row.productName)) {
            String nameKey = normalizeKey(row.productName);
            List<Product2> matches = productIndex.byName.get(nameKey);
            if (matches != null && matches.size() == 1) {
                return matches[0];
            }
        }
        return null;
    }

    private static LinePlan emptyLinePlan(String lineName) {
        LinePlan plan = new LinePlan();
        plan.lineName = lineName;
        plan.status = 'empty';
        plan.products = emptySection();
        plan.specialties = emptySection();
        plan.classes = emptySection();
        plan.errors = new List<String>();
        plan.warnings = new List<String>();
        return plan;
    }

    private static SectionPlan emptySection() {
        SectionPlan section = new SectionPlan();
        section.active = false;
        section.total = 0;
        section.added = 0;
        section.updated = 0;
        section.removed = 0;
        return section;
    }

    private static Decimal normalizePercent(Decimal value) {
        if (value == null) {
            return null;
        }
        return PromoGridAdminController.displayPercent(value);
    }

    private static String normalizeKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String value = raw.trim().toUpperCase();
        value = value.replaceAll('[\\s\\-]+', '_');
        value = value.replaceAll('_+', '_');
        return value;
    }

    private static List<String> splitMirrorLabels(String raw) {
        List<String> labels = new List<String>();
        if (String.isBlank(raw)) {
            return labels;
        }
        for (String part : raw.split('[;,]')) {
            if (String.isNotBlank(part)) {
                labels.add(part.trim());
            }
        }
        return labels;
    }

    private class TerritoryNameComparator implements Comparator<Territory2> {
        public Integer compare(Territory2 a, Territory2 b) {
            String left = a != null && a.Name != null ? a.Name : '';
            String right = b != null && b.Name != null ? b.Name : '';
            return left.compareTo(right);
        }
    }
}
