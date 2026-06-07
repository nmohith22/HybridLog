final List<Map<String, dynamic>> initialExercises = [
  // ==========================================
  // --- CHEST (Anterior Torso) ---
  // ==========================================
  {"name": "Barbell Bench Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Dumbbell Bench Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Incline Barbell Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]}, // Upper focus
  {"name": "Incline Dumbbell Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Decline Barbell Press", "primary": "chest", "secondary": ["triceps"]},
  {"name": "Hammer Strength Wide Chest Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Hammer Strength ISO-Lateral Incline Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Hammer Strength ISO-Lateral Decline Press", "primary": "chest", "secondary": ["triceps"]},
  {"name": "Life Fitness Insignia Chest Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Life Fitness Insignia Incline Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Life Fitness Pro2 Chest Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Life Fitness Pro2 Incline Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Hoist Roc-it Chest Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Hoist Roc-it Incline Press", "primary": "chest", "secondary": ["front_deltoids", "triceps"]},
  {"name": "Cable Fly (Middle)", "primary": "chest", "secondary": ["front_deltoids"]},
  {"name": "Cable Fly (High to Low)", "primary": "chest", "secondary": []}, // Lower focus
  {"name": "Cable Fly (Low to High)", "primary": "chest", "secondary": ["front_deltoids"]}, // Upper focus
  {"name": "Dumbbell Flyes", "primary": "chest", "secondary": ["front_deltoids"]},
  {"name": "Pec Deck Machine", "primary": "chest", "secondary": []},
  {"name": "Dips (Chest Focus)", "primary": "chest", "secondary": ["triceps", "front_deltoids"]},
  {"name": "Weighted Dips (Chest)", "primary": "chest", "secondary": ["triceps", "front_deltoids"]},
  {"name": "Push-ups", "primary": "chest", "secondary": ["triceps", "front_deltoids"]},

  // ==========================================
  // --- DELTOIDS ---
  // ==========================================
  {"name": "Overhead Barbell Press", "primary": "front_deltoids", "secondary": ["triceps", "side_deltoids", "traps"]},
  {"name": "Seated Dumbbell Press", "primary": "front_deltoids", "secondary": ["triceps", "side_deltoids"]},
  {"name": "Hammer Strength ISO-Lateral Shoulder Press", "primary": "front_deltoids", "secondary": ["triceps", "side_deltoids"]},
  {"name": "Life Fitness Insignia Shoulder Press", "primary": "front_deltoids", "secondary": ["triceps", "side_deltoids"]},
  {"name": "Hoist Roc-it Shoulder Press", "primary": "front_deltoids", "secondary": ["triceps", "side_deltoids"]},
  {"name": "Lateral Raise Machine (Life Fitness)", "primary": "side_deltoids", "secondary": ["front_deltoids"]},
  {"name": "Lateral Raise Machine (Hammer)", "primary": "side_deltoids", "secondary": ["front_deltoids"]},
  {"name": "Dumbbell Lateral Raise", "primary": "side_deltoids", "secondary": ["front_deltoids"]},
  {"name": "Cable Lateral Raise", "primary": "side_deltoids", "secondary": ["front_deltoids"]},
  {"name": "Dumbbell Front Raise", "primary": "front_deltoids", "secondary": ["side_deltoids"]},
  {"name": "Cable Front Raise", "primary": "front_deltoids", "secondary": ["side_deltoids"]},
  {"name": "Dumbbell Rear Delt Fly", "primary": "back_deltoids", "secondary": ["traps", "lats"]},
  {"name": "Cable Rear Delt Fly", "primary": "back_deltoids", "secondary": ["traps", "lats"]},
  {"name": "Reverse Pec Deck (Life Fitness)", "primary": "back_deltoids", "secondary": ["traps"]},
  {"name": "Hammer Strength Rear Delt", "primary": "back_deltoids", "secondary": ["traps"]},
  {"name": "Cable Face Pulls", "primary": "back_deltoids", "secondary": ["traps", "side_deltoids"]},
  {"name": "Upright Row (EZ Bar)", "primary": "side_deltoids", "secondary": ["traps", "biceps"]},
  {"name": "Cable Upright Row", "primary": "side_deltoids", "secondary": ["traps", "biceps"]},

  // ==========================================
  // --- BACK (Posterior Torso) ---
  // ==========================================
  {"name": "Hammer Strength ISO-Lateral Lat Pulldown", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Hammer Strength ISO-Lateral Front Pulldown", "primary": "lats", "secondary": ["biceps", "back_deltoids", "traps"]},
  {"name": "Hammer Strength ISO-Lateral Dy-Row", "primary": "lats", "secondary": ["biceps", "traps", "back_deltoids"]},
  {"name": "Hammer Strength ISO-Lateral High Row", "primary": "lats", "secondary": ["traps", "biceps", "back_deltoids"]},
  {"name": "Hammer Strength ISO-Lateral Low Row", "primary": "lats", "secondary": ["traps", "biceps", "back_deltoids"]},
  {"name": "Hammer Strength ISO-Lateral Row", "primary": "lats", "secondary": ["biceps", "traps"]},
  {"name": "Life Fitness Insignia Lat Pulldown", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Life Fitness Insignia Row", "primary": "lats", "secondary": ["biceps", "traps", "back_deltoids"]},
  {"name": "Life Fitness Pro2 Lat Pulldown", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Life Fitness Pro2 Seated Row", "primary": "lats", "secondary": ["biceps", "traps", "back_deltoids"]},
  {"name": "Hoist Roc-it Lat Pulldown", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Hoist Roc-it Seated Row", "primary": "lats", "secondary": ["biceps", "traps"]},
  {"name": "Cable Lat Pulldown (Wide Grip)", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Cable Lat Pulldown (Neutral Grip)", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Cable Lat Pulldown (Reverse Grip)", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Cable Seated Row", "primary": "lats", "secondary": ["biceps", "traps", "back_deltoids"]},
  {"name": "Cable Straight Arm Pulldown", "primary": "lats", "secondary": ["triceps"]},
  {"name": "Barbell Deadlift", "primary": "lower_back", "secondary": ["glutes", "hamstrings", "traps", "forearm"]},
  {"name": "Barbell Row", "primary": "lats", "secondary": ["biceps", "traps", "lower_back"]},
  {"name": "One Arm Dumbbell Row", "primary": "lats", "secondary": ["biceps", "traps", "back_deltoids"]},
  {"name": "T-Bar Row", "primary": "lats", "secondary": ["biceps", "traps", "lower_back"]},
  {"name": "Hyperextensions", "primary": "lower_back", "secondary": ["glutes", "hamstrings"]},
  {"name": "Life Fitness Back Extension", "primary": "lower_back", "secondary": ["glutes"]},
  {"name": "Shrugs (Barbell)", "primary": "traps", "secondary": ["forearm"]},
  {"name": "Shrugs (Dumbbell)", "primary": "traps", "secondary": ["forearm"]},
  {"name": "Pull-ups", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},
  {"name": "Chin-ups", "primary": "biceps", "secondary": ["lats", "back_deltoids"]},
  {"name": "Weighted Pull-ups", "primary": "lats", "secondary": ["biceps", "back_deltoids"]},

  // ==========================================
  // --- BICEPS ---
  // ==========================================
  {"name": "Barbell Bicep Curl", "primary": "biceps", "secondary": ["forearm"]},
  {"name": "EZ Bar Bicep Curl (Close Grip)", "primary": "bicep_long_head", "secondary": ["bicep_short_head", "forearm"]},
  {"name": "EZ Bar Bicep Curl (Wide Grip)", "primary": "bicep_short_head", "secondary": ["bicep_long_head", "forearm"]},
  {"name": "Dumbbell Bicep Curl", "primary": "biceps", "secondary": ["forearm"]},
  {"name": "Incline Dumbbell Curl", "primary": "bicep_long_head", "secondary": ["bicep_short_head"]},
  {"name": "Concentration Curl", "primary": "bicep_short_head", "secondary": []},
  {"name": "Dumbbell Hammer Curl", "primary": "biceps", "secondary": ["forearm"]}, // Brachialis focus
  {"name": "Cable Hammer Curl (Rope)", "primary": "biceps", "secondary": ["forearm"]},
  {"name": "Preacher Curl Machine", "primary": "bicep_short_head", "secondary": ["bicep_long_head"]},
  {"name": "Barbell Preacher Curl", "primary": "bicep_short_head", "secondary": ["bicep_long_head"]},
  {"name": "Life Fitness Insignia Bicep Curl", "primary": "biceps", "secondary": ["forearm"]},
  {"name": "Life Fitness Pro2 Bicep Curl", "primary": "biceps", "secondary": ["forearm"]},
  {"name": "Hoist Roc-it Bicep Curl", "primary": "biceps", "secondary": ["forearm"]},
  {"name": "Cable Bicep Curl (Straight Bar)", "primary": "biceps", "secondary": ["forearm"]},

  // ==========================================
  // --- TRICEPS ---
  // ==========================================
  {"name": "Cable Tricep Pushdown (Straight Bar)", "primary": "triceps", "secondary": []},
  {"name": "Cable Tricep Pushdown (V-Bar)", "primary": "triceps", "secondary": []},
  {"name": "Cable Tricep Pushdown (Rope)", "primary": "triceps", "secondary": []},
  {"name": "Cable Overhead Tricep Extension (Rope)", "primary": "tricep_long_head", "secondary": ["triceps"]},
  {"name": "Dumbbell Overhead Tricep Extension", "primary": "tricep_long_head", "secondary": ["triceps"]},
  {"name": "Skull Crushers (EZ Bar)", "primary": "tricep_long_head", "secondary": ["triceps"]},
  {"name": "Close Grip Barbell Bench Press", "primary": "triceps", "secondary": ["chest", "front_deltoids"]},
  {"name": "Tricep Dip Machine", "primary": "triceps", "secondary": ["chest", "front_deltoids"]},
  {"name": "Dips (Tricep Focus)", "primary": "triceps", "secondary": ["chest", "front_deltoids"]},
  {"name": "Weighted Dips (Tricep)", "primary": "triceps", "secondary": ["chest", "front_deltoids"]},
  {"name": "Life Fitness Insignia Tricep Extension", "primary": "triceps", "secondary": []},
  {"name": "Life Fitness Pro2 Tricep Extension", "primary": "triceps", "secondary": []},
  {"name": "Hammer Strength ISO-Lateral Dips", "primary": "triceps", "secondary": ["chest"]},

  // ==========================================
  // --- LEGS (Quads, Hamstrings, Glutes) ---
  // ==========================================
  {"name": "Barbell Back Squat", "primary": "quads", "secondary": ["glutes", "lower_back", "hamstrings"]},
  {"name": "Barbell Front Squat", "primary": "quads", "secondary": ["upper_back", "glutes"]},
  {"name": "Hack Squat Machine", "primary": "quads", "secondary": ["glutes", "hamstrings"]},
  {"name": "Leg Press (Life Fitness Horizontal)", "primary": "quads", "secondary": ["glutes", "hamstrings"]},
  {"name": "Leg Press (Hammer Strength 45-Degree)", "primary": "quads", "secondary": ["glutes", "hamstrings"]},
  {"name": "Hoist Roc-it Leg Press", "primary": "quads", "secondary": ["glutes", "hamstrings"]},
  {"name": "Life Fitness Insignia Leg Extension", "primary": "quads", "secondary": []},
  {"name": "Hammer Strength Leg Extension", "primary": "quads", "secondary": []},
  {"name": "Hoist Roc-it Leg Extension", "primary": "quads", "secondary": []},
  {"name": "Life Fitness Insignia Seated Leg Curl", "primary": "hamstrings", "secondary": ["calves"]},
  {"name": "Hammer Strength Seated Leg Curl", "primary": "hamstrings", "secondary": ["calves"]},
  {"name": "Life Fitness Pro2 Lying Leg Curl", "primary": "hamstrings", "secondary": ["calves"]},
  {"name": "Romanian Deadlift (Barbell)", "primary": "hamstrings", "secondary": ["glutes", "lower_back"]},
  {"name": "Romanian Deadlift (Dumbbell)", "primary": "hamstrings", "secondary": ["glutes", "lower_back"]},
  {"name": "Bulgarian Split Squat (Dumbbell)", "primary": "quads", "secondary": ["glutes", "hamstrings"]},
  {"name": "Walking Lunges (Dumbbell)", "primary": "quads", "secondary": ["glutes", "hamstrings"]},
  {"name": "Standing Calf Raise Machine", "primary": "calves", "secondary": []},
  {"name": "Seated Calf Raise Machine", "primary": "calves", "secondary": []},
  {"name": "Hammer Strength Calf Raise", "primary": "calves", "secondary": []},
  {"name": "Life Fitness Insignia Calf Extension", "primary": "calves", "secondary": []},
  {"name": "Life Fitness Insignia Hip Abduction", "primary": "glutes", "secondary": []},
  {"name": "Life Fitness Insignia Hip Adduction", "primary": "adductors", "secondary": []},
  {"name": "Glute Kickback Machine", "primary": "glutes", "secondary": ["hamstrings"]},

  // ==========================================
  // --- ABS & CORE ---
  // ==========================================
  {"name": "Cable Crunch", "primary": "abs", "secondary": []},
  {"name": "Life Fitness Insignia Abdominal", "primary": "abs", "secondary": []},
  {"name": "Life Fitness Pro2 Abdominal", "primary": "abs", "secondary": []},
  {"name": "Hanging Leg Raise", "primary": "abs", "secondary": ["obliques"]},
  {"name": "Captains Chair Leg Raise", "primary": "abs", "secondary": ["obliques"]},
  {"name": "Russian Twist (Dumbbell)", "primary": "obliques", "secondary": ["abs"]},
  {"name": "Cable Woodchopper", "primary": "obliques", "secondary": ["abs"]},
  {"name": "Life Fitness Insignia Torso Rotation", "primary": "obliques", "secondary": ["abs"]},
  {"name": "Plank", "primary": "abs", "secondary": ["lower_back"]}
];
