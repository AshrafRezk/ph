List<String> reps = new List<String>{
    'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
};
Integer created = MedicalRep360Seed.ensureDemoCoachingEventsForReps(reps);
System.debug('Created ' + created + ' coaching events.');
