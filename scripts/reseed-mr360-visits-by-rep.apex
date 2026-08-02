List<String> reps = new List<String>{
    'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
};
for (String rep : reps) {
    MedicalRep360Seed.SeedResult result = MedicalRep360Seed.reseedVisitsForRep(rep);
    System.debug(rep + ': ' + result.message);
}
