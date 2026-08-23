"""Catalogue of demo professionals used by the seed_demo_professionals command.

This is presentation data, not product logic: it exists so the application can
be shown to someone with realistic content on every screen. It is deliberately
kept out of the management command itself so the command stays readable.

Constraints this data has to respect (they come from the Free plan and from
template validation, and the seed asserts them before writing anything):

  * 5 templates per professional, 8 fields per template
  * 3 groups, 1 lead form, 5 resource categories, 3 subcategories per category,
    30 resources
  * template field types are limited to: number, short_text, long_text,
    yes_no, dropdown, rating -- there is no date type, so dates that belong to
    a tracked record are collected as short text

Each template field carries a `sample` spec telling the seed how to invent a
plausible value for it. The vocabulary is documented in the command.
"""


def _field(key, label, field_type, sample, placeholder='', options=None, scale=None):
  return {
    'key': key,
    'label': label,
    'field_type': field_type,
    'placeholder': placeholder,
    'options': list(options or []),
    'scale': scale,
    'sample': sample,
  }


# --------------------------------------------------------------------------
# 1. Personal fitness trainer
# --------------------------------------------------------------------------

FITNESS_TEMPLATES = [
  {
    'name': 'Workout Progress',
    'purpose': 'Session-by-session record of what was trained, how much, and how hard it felt.',
    'cadence': 'daily',
    'accent': 'blue',
    'days_per_week': 5,
    'fields': [
      _field('workout_type', 'Workout type', 'dropdown', ('choice', ['Upper Body', 'Lower Body', 'Full Body', 'Push', 'Pull', 'Conditioning', 'Mobility']), options=['Upper Body', 'Lower Body', 'Full Body', 'Push', 'Pull', 'Conditioning', 'Mobility']),
      _field('session_name', 'Session name', 'short_text', ('choice', ['Strength A', 'Strength B', 'Hypertrophy A', 'Hypertrophy B', 'Conditioning circuit', 'Deload session']), placeholder='Strength A'),
      _field('duration_minutes', 'Duration (minutes)', 'number', ('int', 35, 75), placeholder='60'),
      _field('sets', 'Sets completed', 'number', ('int', 12, 24), placeholder='18'),
      _field('reps', 'Total reps', 'number', ('int', 90, 220), placeholder='140'),
      _field('load_kg', 'Working load (kg)', 'number', ('trend', 32, 58, 4, 1), placeholder='45'),
      _field('completion_percent', 'Completion %', 'pct', ('pct', 70, 100), placeholder='100'),
      _field('difficulty', 'Difficulty', 'rating', ('rating', 2, 5), scale=5),
    ],
  },
  {
    'name': 'Nutrition Log',
    'purpose': 'Daily intake and adherence, so nutrition is discussed from data rather than memory.',
    'cadence': 'daily',
    'accent': 'green',
    'days_per_week': 7,
    'fields': [
      _field('calories', 'Calories consumed', 'number', ('int', 1650, 2650), placeholder='2100'),
      _field('protein_g', 'Protein (g)', 'number', ('int', 95, 175), placeholder='140'),
      _field('carbs_g', 'Carbohydrates (g)', 'number', ('int', 150, 300), placeholder='220'),
      _field('fat_g', 'Fat (g)', 'number', ('int', 45, 90), placeholder='65'),
      _field('water_litres', 'Water intake (litres)', 'number', ('float', 1.6, 3.6, 1), placeholder='2.5'),
      _field('meals_completed', 'Meals completed', 'number', ('int', 2, 5), placeholder='4'),
      _field('adherence_percent', 'Diet adherence %', 'pct', ('pct', 60, 100), placeholder='85'),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Hit the protein target comfortably. Evening snack was the only extra.',
        'Ate out at lunch, kept portions sensible and skipped the dessert.',
        'Long day, dinner was late but the plan was still followed.',
        'Water was low again in the afternoon. Setting a reminder for tomorrow.',
        'Good day overall. Meal prep on Sunday is clearly paying off.',
      ])),
    ],
  },
  {
    'name': 'Body Progress',
    'purpose': 'Weekly measurements, so progress is judged on trend rather than a single weigh-in.',
    'cadence': 'weekly',
    'accent': 'purple',
    'fields': [
      _field('body_weight_kg', 'Body weight (kg)', 'number', ('trend', 88.5, 79.4, 0.7, 1), placeholder='82.4'),
      _field('waist_cm', 'Waist (cm)', 'number', ('trend', 98, 88, 1.0, 1), placeholder='92'),
      _field('chest_cm', 'Chest (cm)', 'number', ('trend', 102, 105, 0.8, 1), placeholder='104'),
      _field('arms_cm', 'Arms (cm)', 'number', ('trend', 33, 36, 0.4, 1), placeholder='35'),
      _field('body_fat_percent', 'Body fat %', 'number', ('trend', 27, 20, 0.8, 1), placeholder='23'),
      _field('progress_notes', 'Progress notes', 'long_text', ('text', [
        'Waist down again this week. Clothes fitting noticeably better.',
        'Weight flat, measurements down. Exactly what we want to see.',
        'Travel week, so holding steady is a good result.',
        'Strength up on every main lift while weight came down slightly.',
      ])),
    ],
  },
  {
    'name': 'Weekly Check-In',
    'purpose': 'The weekly conversation starter: what happened, what got in the way, what changes.',
    'cadence': 'weekly',
    'accent': 'orange',
    'fields': [
      _field('workouts_completed', 'Workouts completed', 'number', ('int', 2, 6), placeholder='4'),
      _field('nutrition_adherence', 'Nutrition adherence %', 'pct', ('pct', 65, 98)),
      _field('energy', 'Energy', 'rating', ('rating', 2, 5), scale=5),
      _field('sleep_quality', 'Sleep quality', 'rating', ('rating', 2, 5), scale=5),
      _field('overall_progress', 'Overall progress', 'rating', ('rating', 3, 5), scale=5),
      _field('challenges', 'Challenges', 'long_text', ('text', [
        'Work deadlines pushed two sessions later in the evening.',
        'Weekend meals were harder to control than weekdays.',
        'Sleep was short midweek, which showed up in session energy.',
        'Nothing major this week. Everything went close to plan.',
      ])),
      _field('comments', 'Comments', 'long_text', ('text', [
        'Happy with how the training felt. Ready to add load next week.',
        'Would like an alternative for the overhead press, shoulder feels tight.',
        'Please keep the same structure, it is working.',
      ])),
    ],
  },
  {
    'name': 'Goal Tracker',
    'purpose': 'The handful of outcomes the whole plan is pointed at, reviewed monthly.',
    'cadence': 'monthly',
    'accent': 'green',
    'fields': [
      _field('goal_name', 'Goal', 'short_text', ('choice', ['Lose 8 kg', 'Squat bodyweight for 5', 'Run 5 km without stopping', '10,000 steps daily', 'Three sessions every week'])),
      _field('starting_value', 'Starting value', 'number', ('int', 60, 95)),
      _field('target_value', 'Target value', 'number', ('int', 100, 140)),
      _field('current_value', 'Current value', 'number', ('int', 70, 120)),
      _field('target_date', 'Target date', 'short_text', ('datestr', 30, 120), placeholder='31 December 2026'),
      _field('status', 'Status', 'dropdown', ('choice', ['On track', 'Ahead of plan', 'Slightly behind', 'Achieved']), options=['On track', 'Ahead of plan', 'Slightly behind', 'Achieved', 'Paused']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Steady progress. No change to the plan needed.',
        'Ahead of schedule, so the target has been raised slightly.',
        'Behind after a travel month. Extending the target date by two weeks.',
      ])),
    ],
  },
]


# --------------------------------------------------------------------------
# 2. Academic / coding tutor
# --------------------------------------------------------------------------

TUTOR_TEMPLATES = [
  {
    'name': 'Study Progress',
    'purpose': 'What was studied each session, how long for, and how confident it left the student.',
    'cadence': 'daily',
    'accent': 'blue',
    'days_per_week': 5,
    'fields': [
      _field('subject', 'Subject', 'dropdown', ('choice', ['Python', 'Data Structures', 'Algorithms', 'SQL', 'Mathematics', 'System Design']), options=['Python', 'Data Structures', 'Algorithms', 'SQL', 'Mathematics', 'System Design']),
      _field('topic', 'Topic', 'short_text', ('choice', ['Recursion', 'Hash maps', 'Binary search', 'Joins and indexes', 'Dynamic programming', 'Big-O analysis', 'Linked lists', 'Probability'])),
      _field('duration_minutes', 'Study duration (minutes)', 'number', ('int', 30, 120)),
      _field('practice_completed', 'Practice completed?', 'yes_no', ('bool', 0.82)),
      _field('confidence', 'Confidence', 'rating', ('trend_rating', 2, 5), scale=5),
      _field('difficulty', 'Difficulty', 'rating', ('rating', 2, 5), scale=5),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Worked through five practice problems, two needed a hint.',
        'Concept clicked once we drew it out. Repeat next session to be sure.',
        'Struggled with edge cases. Assigned three more problems for practice.',
        'Very strong session, finished early and asked good questions.',
      ])),
    ],
  },
  {
    'name': 'Assessment Results',
    'purpose': 'Every test and mock, scored and fed back, so improvement is measurable.',
    'cadence': 'weekly',
    'accent': 'purple',
    'fields': [
      _field('assessment_name', 'Assessment', 'short_text', ('choice', ['Weekly quiz', 'Unit test', 'Mock interview', 'Practice paper', 'Coding challenge'])),
      _field('topic', 'Topic', 'short_text', ('choice', ['Arrays and strings', 'Recursion', 'SQL queries', 'Graphs', 'Object-oriented design'])),
      _field('score', 'Score', 'number', ('trend', 11, 18, 1.5, 0)),
      _field('maximum_score', 'Maximum score', 'number', ('const', 20)),
      _field('percentage', 'Percentage', 'pct', ('pct', 55, 95)),
      _field('attempt_number', 'Attempt number', 'number', ('int', 1, 2)),
      _field('feedback', 'Feedback', 'long_text', ('text', [
        'Strong on implementation, lost marks on complexity analysis.',
        'Much cleaner than the previous attempt. Keep the same approach.',
        'Careless errors under time pressure. Practise with a timer this week.',
        'Excellent. Ready to move up a difficulty level.',
      ])),
    ],
  },
  {
    'name': 'Assignment Tracker',
    'purpose': 'What was set, whether it arrived on time, and how it scored.',
    'cadence': 'weekly',
    'accent': 'orange',
    'fields': [
      _field('assignment', 'Assignment', 'short_text', ('choice', ['Recursion problem set', 'SQL exercises', 'Mini project: to-do API', 'Algorithm write-up', 'Debugging exercise'])),
      _field('due_date', 'Due date', 'short_text', ('datestr', 3, 10)),
      _field('submitted', 'Submitted?', 'yes_no', ('bool', 0.85)),
      _field('status', 'Status', 'dropdown', ('choice', ['Submitted on time', 'Submitted late', 'In progress', 'Not started']), options=['Submitted on time', 'Submitted late', 'In progress', 'Not started']),
      _field('score', 'Score', 'number', ('int', 12, 20)),
      _field('feedback', 'Feedback', 'long_text', ('text', [
        'Correct solution, but the variable naming makes it hard to follow.',
        'Good structure. Add comments explaining the recursive step.',
        'Handed in late but the work itself is solid.',
        'Best submission so far. Nothing to correct.',
      ])),
    ],
  },
  {
    'name': 'Session Log',
    'purpose': 'Attendance and participation, session by session.',
    'cadence': 'daily',
    'accent': 'blue',
    'days_per_week': 3,
    'fields': [
      _field('session_topic', 'Session topic', 'short_text', ('choice', ['Recursion practice', 'Interview preparation', 'SQL drills', 'Project review', 'Doubt clearing'])),
      _field('attendance', 'Attendance', 'dropdown', ('weighted', [('Present', 0.86), ('Late', 0.09), ('Absent', 0.05)]), options=['Present', 'Late', 'Absent']),
      _field('duration_minutes', 'Duration (minutes)', 'number', ('int', 45, 90)),
      _field('participation', 'Participation', 'rating', ('rating', 3, 5), scale=5),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Engaged throughout and asked for extra practice.',
        'Quiet at the start, opened up once we moved to the whiteboard.',
        'Joined ten minutes late, caught up quickly.',
      ])),
    ],
  },
  {
    'name': 'Learning Goals',
    'purpose': 'The longer-range targets behind the weekly work.',
    'cadence': 'monthly',
    'accent': 'green',
    'fields': [
      _field('goal', 'Goal', 'short_text', ('choice', ['Clear the placement coding round', 'Score above 85% in unit tests', 'Finish the data structures track', 'Build and deploy one project'])),
      _field('target_date', 'Target date', 'short_text', ('datestr', 30, 90)),
      _field('progress_percent', 'Progress %', 'pct', ('pct', 30, 95)),
      _field('status', 'Status', 'dropdown', ('choice', ['On track', 'Slightly behind', 'Ahead of plan', 'Achieved']), options=['On track', 'Slightly behind', 'Ahead of plan', 'Achieved']),
      _field('challenges', 'Challenges', 'long_text', ('text', [
        'College exams reduced practice time this month.',
        'Confidence is the limiter now rather than knowledge.',
        'No blockers. Consistency has been excellent.',
      ])),
      _field('tutor_notes', 'Tutor notes', 'long_text', ('text', [
        'Shift the balance towards timed practice from next week.',
        'Ready for harder problems. Moving up a tier.',
        'Keep revising the fundamentals for one more week before moving on.',
      ])),
    ],
  },
]


# --------------------------------------------------------------------------
# 3. Career / job coach
# --------------------------------------------------------------------------

CAREER_TEMPLATES = [
  {
    'name': 'Job Application Tracker',
    'purpose': 'Every application in one place, with where it came from and what happens next.',
    'cadence': 'daily',
    'accent': 'blue',
    'days_per_week': 4,
    'fields': [
      _field('company', 'Company', 'short_text', ('choice', ['Northwind Analytics', 'Bluewave Systems', 'Harbour Logistics', 'Kestrel Health', 'Lantern Retail', 'Orchid Software', 'Summit Financial'])),
      _field('job_title', 'Job title', 'short_text', ('choice', ['Data Analyst', 'Operations Associate', 'Backend Developer', 'Project Coordinator', 'Customer Success Manager'])),
      _field('location', 'Location', 'short_text', ('choice', ['Remote', 'Hybrid - city centre', 'On site', 'Remote (same time zone)'])),
      _field('source', 'Application source', 'dropdown', ('choice', ['Company site', 'LinkedIn', 'Referral', 'Job board', 'Recruiter']), options=['Company site', 'LinkedIn', 'Referral', 'Job board', 'Recruiter']),
      _field('status', 'Status', 'dropdown', ('weighted', [('Applied', 0.45), ('Screening', 0.2), ('Interviewing', 0.15), ('Offer', 0.05), ('Rejected', 0.15)]), options=['Applied', 'Screening', 'Interviewing', 'Offer', 'Rejected', 'Withdrawn']),
      _field('follow_up_date', 'Follow-up date', 'short_text', ('datestr', 4, 14)),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Tailored the CV to the job description and mentioned the referral.',
        'Recruiter replied within a day asking for availability.',
        'No response yet. Following up at the end of the week.',
        'Application submitted through the referral rather than the job board.',
      ])),
    ],
  },
  {
    'name': 'Interview Tracker',
    'purpose': 'Each round, how prepared it felt, and what came out of it.',
    'cadence': 'weekly',
    'accent': 'purple',
    'fields': [
      _field('company', 'Company', 'short_text', ('choice', ['Northwind Analytics', 'Bluewave Systems', 'Kestrel Health', 'Orchid Software'])),
      _field('role', 'Role', 'short_text', ('choice', ['Data Analyst', 'Backend Developer', 'Operations Associate'])),
      _field('round', 'Interview round', 'dropdown', ('choice', ['Screening call', 'Technical round 1', 'Technical round 2', 'Hiring manager', 'Final round']), options=['Screening call', 'Technical round 1', 'Technical round 2', 'Hiring manager', 'Final round']),
      _field('interview_type', 'Interview type', 'dropdown', ('choice', ['Video', 'Phone', 'In person', 'Take-home task']), options=['Video', 'Phone', 'In person', 'Take-home task']),
      _field('status', 'Status', 'dropdown', ('weighted', [('Completed', 0.7), ('Scheduled', 0.2), ('Cancelled', 0.1)]), options=['Scheduled', 'Completed', 'Cancelled']),
      _field('preparation_rating', 'Preparation', 'rating', ('trend_rating', 2, 5), scale=5),
      _field('outcome', 'Outcome', 'dropdown', ('weighted', [('Moved to next round', 0.4), ('Awaiting decision', 0.35), ('Not selected', 0.25)]), options=['Moved to next round', 'Awaiting decision', 'Not selected', 'Offer']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Answered the situational questions well. Struggled to quantify impact.',
        'Prepared three stories in advance and used two of them.',
        'Technical round went better than expected. Follow-up in a week.',
      ])),
    ],
  },
  {
    'name': 'Skill Development',
    'purpose': 'The skills being built alongside the search, and how they are progressing.',
    'cadence': 'daily',
    'accent': 'green',
    'days_per_week': 3,
    'fields': [
      _field('skill', 'Skill', 'short_text', ('choice', ['SQL', 'Excel modelling', 'Public speaking', 'Python', 'Stakeholder communication', 'Power BI'])),
      _field('activity', 'Learning activity', 'short_text', ('choice', ['Online course module', 'Practice exercises', 'Mock presentation', 'Reading and notes', 'Portfolio project'])),
      _field('time_spent_minutes', 'Time spent (minutes)', 'number', ('int', 25, 120)),
      _field('confidence', 'Confidence', 'rating', ('trend_rating', 2, 5), scale=5),
      _field('progress_percent', 'Progress %', 'pct', ('pct', 20, 95)),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Finished the module and redid the exercises without notes.',
        'Recorded the practice answer and reviewed it. Pace is too fast.',
        'Added the project to the portfolio and linked it on the CV.',
      ])),
    ],
  },
  {
    'name': 'Weekly Goals',
    'purpose': 'A small number of commitments each week, reviewed honestly.',
    'cadence': 'weekly',
    'accent': 'orange',
    'fields': [
      _field('goal', 'Goal', 'short_text', ('choice', ['Send five tailored applications', 'Complete two mock interviews', 'Reach out to three contacts', 'Finish the portfolio project', 'Rewrite the CV summary'])),
      _field('target', 'Target', 'short_text', ('choice', ['5 applications', '2 mock interviews', '3 conversations', '1 project', '1 rewrite'])),
      _field('completion_percent', 'Completion %', 'pct', ('pct', 40, 100)),
      _field('status', 'Status', 'dropdown', ('weighted', [('Completed', 0.55), ('Partially completed', 0.3), ('Carried over', 0.15)]), options=['Completed', 'Partially completed', 'Carried over', 'Not started']),
      _field('challenges', 'Challenges', 'long_text', ('text', [
        'Tailoring each application takes longer than expected.',
        'Notice period at the current job limited interview availability.',
        'No real blockers this week.',
      ])),
      _field('next_action', 'Next action', 'long_text', ('text', [
        'Prepare two more stories for behavioural rounds.',
        'Follow up on the three applications sent last week.',
        'Book the mock interview for Thursday morning.',
      ])),
    ],
  },
  {
    'name': 'Networking Tracker',
    'purpose': 'Conversations rather than applications: who was contacted, and what follows.',
    'cadence': 'weekly',
    'accent': 'blue',
    'fields': [
      _field('contact', 'Contact or organisation', 'short_text', ('choice', ['Former manager', 'Alumni group', 'Recruiter at Bluewave', 'Meetup contact', 'Team lead at Kestrel'])),
      _field('interaction_type', 'Interaction type', 'dropdown', ('choice', ['Message', 'Call', 'Coffee chat', 'Event', 'Referral request']), options=['Message', 'Call', 'Coffee chat', 'Event', 'Referral request']),
      _field('follow_up_required', 'Follow-up required?', 'yes_no', ('bool', 0.6)),
      _field('follow_up_date', 'Follow-up date', 'short_text', ('datestr', 5, 21)),
      _field('status', 'Status', 'dropdown', ('weighted', [('Replied', 0.5), ('Awaiting reply', 0.35), ('Closed', 0.15)]), options=['Awaiting reply', 'Replied', 'Meeting booked', 'Closed']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Sent a short message referencing the talk they gave last month.',
        'Agreed to a fifteen-minute call next week.',
        'Offered to pass the CV to their hiring manager.',
      ])),
    ],
  },
]


# --------------------------------------------------------------------------
# 4. Sports coach
# --------------------------------------------------------------------------

SPORTS_TEMPLATES = [
  {
    'name': 'Training Log',
    'purpose': 'What was trained, how hard, and how much of the plan was actually completed.',
    'cadence': 'daily',
    'accent': 'blue',
    'days_per_week': 5,
    'fields': [
      _field('training_type', 'Training type', 'dropdown', ('choice', ['Technical', 'Tactical', 'Strength', 'Speed', 'Endurance', 'Recovery']), options=['Technical', 'Tactical', 'Strength', 'Speed', 'Endurance', 'Recovery']),
      _field('duration_minutes', 'Duration (minutes)', 'number', ('int', 45, 120)),
      _field('intensity', 'Intensity', 'rating', ('rating', 4, 9), scale=10),
      _field('drills_completed', 'Drills completed', 'number', ('int', 4, 12)),
      _field('completion_percent', 'Completion %', 'pct', ('pct', 70, 100)),
      _field('coach_notes', 'Coach notes', 'long_text', ('text', [
        'Sharp in the first half of the session, faded in the last twenty minutes.',
        'Best technical work of the block. Repeat this drill progression.',
        'Held back deliberately, still inside the return-to-play plan.',
        'Good intensity throughout. Ready for a harder week.',
      ])),
    ],
  },
  {
    'name': 'Performance Tracker',
    'purpose': 'The measurable tests, tracked against the previous result and the target.',
    'cadence': 'weekly',
    'accent': 'purple',
    'fields': [
      _field('metric', 'Metric or test', 'dropdown', ('choice', ['20m sprint', 'Vertical jump', 'Yo-yo test', 'Agility ladder', 'Endurance run']), options=['20m sprint', 'Vertical jump', 'Yo-yo test', 'Agility ladder', 'Endurance run']),
      _field('result', 'Result', 'number', ('trend', 42, 56, 2, 1)),
      _field('unit', 'Unit', 'short_text', ('choice', ['cm', 'seconds', 'level', 'metres'])),
      _field('previous_result', 'Previous result', 'number', ('trend', 40, 53, 2, 1)),
      _field('target', 'Target', 'number', ('const', 60)),
      _field('coach_notes', 'Coach notes', 'long_text', ('text', [
        'Improvement is holding week to week rather than spiking.',
        'Slight drop, but this was the end of a heavy training block.',
        'New personal best. Target raised for the next block.',
      ])),
    ],
  },
  {
    'name': 'Attendance',
    'purpose': 'Who turned up, when, and how they engaged.',
    'cadence': 'daily',
    'accent': 'orange',
    'days_per_week': 4,
    'fields': [
      _field('session', 'Session', 'short_text', ('choice', ['Morning squad', 'Evening squad', 'Skills session', 'Match preparation', 'Recovery session'])),
      _field('attendance', 'Attendance', 'dropdown', ('weighted', [('Present', 0.88), ('Absent', 0.07), ('Excused', 0.05)]), options=['Present', 'Absent', 'Excused']),
      _field('arrival', 'Arrival', 'dropdown', ('weighted', [('On time', 0.8), ('Early', 0.12), ('Late', 0.08)]), options=['Early', 'On time', 'Late']),
      _field('participation', 'Participation', 'rating', ('rating', 3, 5), scale=5),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Led the warm-up without being asked.',
        'Quiet session, still recovering from the weekend fixture.',
        'Full participation, good communication with the group.',
      ])),
    ],
  },
  {
    'name': 'Recovery Check-In',
    'purpose': 'The readiness picture before training: sleep, soreness, and how recovered they feel.',
    'cadence': 'daily',
    'accent': 'green',
    'days_per_week': 5,
    'fields': [
      _field('energy', 'Energy', 'rating', ('rating', 2, 5), scale=5),
      _field('sleep_hours', 'Sleep (hours)', 'number', ('float', 5.5, 9.0, 1)),
      _field('recovery', 'Recovery', 'rating', ('rating', 2, 5), scale=5),
      _field('soreness', 'Soreness', 'rating', ('rating', 1, 4), scale=5),
      _field('readiness', 'Readiness to train', 'rating', ('rating', 3, 5), scale=5),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Legs still heavy from the weekend. Reduced volume today.',
        'Slept well and feeling sharp.',
        'Late finish at work, short sleep. Kept the session technical.',
      ])),
    ],
  },
  {
    'name': 'Match Review',
    'purpose': 'The post-event record: what happened, what worked, what to work on.',
    'cadence': 'monthly',
    'accent': 'blue',
    'fields': [
      _field('event', 'Event', 'short_text', ('choice', ['League fixture', 'Friendly match', 'Regional qualifier', 'Club championship', 'Inter-club meet'])),
      _field('participation', 'Participation', 'dropdown', ('choice', ['Full match', 'Substitute', 'Partial', 'Did not play']), options=['Full match', 'Substitute', 'Partial', 'Did not play']),
      _field('result', 'Result', 'dropdown', ('weighted', [('Win', 0.45), ('Draw', 0.2), ('Loss', 0.35)]), options=['Win', 'Draw', 'Loss', 'Not applicable']),
      _field('performance_rating', 'Performance', 'rating', ('trend_rating', 3, 5), scale=5),
      _field('strengths', 'Strengths', 'long_text', ('text', [
        'Positioning was excellent and decision making was quick.',
        'Held intensity for the full match without dropping off.',
        'Communication with the back line was the best it has been.',
      ])),
      _field('areas_to_improve', 'Areas to improve', 'long_text', ('text', [
        'First touch under pressure in the final third.',
        'Recovery runs after losing possession.',
        'Set-piece timing needs another week of work.',
      ])),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Reviewed the footage together on Monday.',
        'Confidence is clearly higher than at the start of the season.',
      ])),
    ],
  },
]


# --------------------------------------------------------------------------
# 5. General consultation practice
# --------------------------------------------------------------------------

CONSULT_TEMPLATES = [
  {
    'name': 'Consultation Intake',
    'purpose': 'The first record for a new enquiry: what it is about and how urgent it is.',
    'cadence': 'monthly',
    'accent': 'blue',
    'fields': [
      _field('category', 'Consultation category', 'dropdown', ('choice', ['Business strategy', 'Operations review', 'Compliance', 'Contracts', 'General advisory']), options=['Business strategy', 'Operations review', 'Compliance', 'Contracts', 'General advisory']),
      _field('preferred_date', 'Preferred date', 'short_text', ('datestr', 3, 21)),
      _field('status', 'Status', 'dropdown', ('weighted', [('Scheduled', 0.5), ('Awaiting confirmation', 0.3), ('Completed', 0.2)]), options=['Awaiting confirmation', 'Scheduled', 'Completed', 'Cancelled']),
      _field('priority', 'Priority', 'dropdown', ('weighted', [('Normal', 0.6), ('High', 0.25), ('Low', 0.15)]), options=['Low', 'Normal', 'High', 'Urgent']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Referred by an existing client. Wants an initial scoping call.',
        'Time sensitive: a decision is needed before the quarter closes.',
        'General enquiry, no fixed deadline. Happy to wait for a slot.',
      ])),
    ],
  },
  {
    'name': 'Consultation Record',
    'purpose': 'What was actually discussed in each session and whether anything follows it.',
    'cadence': 'weekly',
    'repeat': 3,
    'accent': 'purple',
    'fields': [
      _field('category', 'Category', 'dropdown', ('choice', ['Business strategy', 'Operations review', 'Compliance', 'Contracts', 'General advisory']), options=['Business strategy', 'Operations review', 'Compliance', 'Contracts', 'General advisory']),
      _field('duration_minutes', 'Duration (minutes)', 'number', ('choice', [30, 45, 60, 90])),
      _field('status', 'Status', 'dropdown', ('weighted', [('Completed', 0.8), ('Rescheduled', 0.12), ('Cancelled', 0.08)]), options=['Completed', 'Rescheduled', 'Cancelled']),
      _field('follow_up_required', 'Follow-up required?', 'yes_no', ('bool', 0.55)),
      _field('follow_up_date', 'Follow-up date', 'short_text', ('datestr', 7, 30)),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Walked through the current process and agreed two immediate changes.',
        'Reviewed the draft and marked the clauses that need rewording.',
        'Mostly a status update. Nothing outstanding from our side.',
        'Agreed to reconvene once the internal numbers are available.',
      ])),
    ],
  },
  {
    'name': 'Follow-Up',
    'purpose': 'The short list of things still owed to a client after a consultation.',
    'cadence': 'monthly',
    'repeat': 2,
    'accent': 'orange',
    'fields': [
      _field('follow_up_type', 'Follow-up type', 'dropdown', ('choice', ['Document review', 'Call', 'Written summary', 'Introduction', 'Check-in']), options=['Document review', 'Call', 'Written summary', 'Introduction', 'Check-in']),
      _field('status', 'Status', 'dropdown', ('weighted', [('Completed', 0.6), ('Open', 0.3), ('Waiting on client', 0.1)]), options=['Open', 'Waiting on client', 'Completed']),
      _field('next_action', 'Next action', 'short_text', ('choice', ['Send the written summary', 'Book the review call', 'Await the signed copy', 'Share the comparison sheet'])),
      _field('next_date', 'Next date', 'short_text', ('datestr', 5, 25)),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Summary sent. Awaiting confirmation that it covers everything.',
        'Client asked for an extra week before the review call.',
        'Closed out. Nothing further outstanding.',
      ])),
    ],
  },
]


# --------------------------------------------------------------------------
# 6. Tax / financial consultation
# --------------------------------------------------------------------------

TAX_TEMPLATES = [
  {
    'name': 'Client Intake',
    'purpose': 'What the client needs help with and when they want it done.',
    'cadence': 'monthly',
    'repeat': 2,
    'accent': 'blue',
    'fields': [
      _field('service_category', 'Service category', 'dropdown', ('choice', ['Individual tax return', 'Business tax return', 'Tax planning', 'Bookkeeping review', 'Notice response']), options=['Individual tax return', 'Business tax return', 'Tax planning', 'Bookkeeping review', 'Notice response']),
      _field('consultation_type', 'Consultation type', 'dropdown', ('choice', ['First consultation', 'Annual filing', 'Ongoing advisory', 'One-off question']), options=['First consultation', 'Annual filing', 'Ongoing advisory', 'One-off question']),
      _field('preferred_date', 'Preferred date', 'short_text', ('datestr', 3, 20)),
      _field('status', 'Status', 'dropdown', ('weighted', [('Scheduled', 0.55), ('Awaiting documents', 0.3), ('Completed', 0.15)]), options=['Awaiting documents', 'Scheduled', 'Completed', 'On hold']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Two income sources this year, including freelance work.',
        'Straightforward return, same structure as last year.',
        'Needs the filing completed before travelling next month.',
      ])),
    ],
  },
  {
    'name': 'Document Checklist',
    'purpose': 'What was asked for, what has arrived, and what is still missing.',
    'cadence': 'weekly',
    'repeat': 3,
    'accent': 'orange',
    'fields': [
      _field('document_category', 'Document category', 'dropdown', ('choice', ['Income statements', 'Bank statements', 'Investment proofs', 'Expense receipts', 'Previous return', 'Identity documents']), options=['Income statements', 'Bank statements', 'Investment proofs', 'Expense receipts', 'Previous return', 'Identity documents']),
      _field('requested_date', 'Requested date', 'short_text', ('datestr', -14, -2)),
      _field('received', 'Received?', 'yes_no', ('bool', 0.72)),
      _field('received_date', 'Received date', 'short_text', ('datestr', -7, 0)),
      _field('review_status', 'Review status', 'dropdown', ('weighted', [('Reviewed', 0.5), ('Pending review', 0.3), ('Clarification needed', 0.2)]), options=['Pending review', 'Reviewed', 'Clarification needed']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'One statement is missing the final quarter. Requested again.',
        'All documents received and legible. Ready for review.',
        'Receipts sent as photographs; asked for the originals.',
      ])),
    ],
  },
  {
    'name': 'Case Progress',
    'purpose': 'Where each case has reached and what is blocking it.',
    'cadence': 'weekly',
    'repeat': 2,
    'accent': 'purple',
    'fields': [
      _field('service_type', 'Service type', 'dropdown', ('choice', ['Individual tax return', 'Business tax return', 'Tax planning', 'Notice response']), options=['Individual tax return', 'Business tax return', 'Tax planning', 'Notice response']),
      _field('current_stage', 'Current stage', 'dropdown', ('choice', ['Document collection', 'Preparation', 'Internal review', 'Client review', 'Filed']), options=['Document collection', 'Preparation', 'Internal review', 'Client review', 'Filed']),
      _field('completion_percent', 'Completion %', 'pct', ('trend', 20, 100, 5, 0)),
      _field('pending_action', 'Pending action', 'short_text', ('choice', ['Awaiting client confirmation', 'Awaiting missing statement', 'Internal review', 'Nothing pending'])),
      _field('follow_up_date', 'Follow-up date', 'short_text', ('datestr', 3, 15)),
      _field('status', 'Status', 'dropdown', ('weighted', [('On track', 0.7), ('Waiting on client', 0.2), ('At risk', 0.1)]), options=['On track', 'Waiting on client', 'At risk', 'Completed']),
      _field('notes', 'Notes', 'long_text', ('text', [
        'Preparation complete, waiting on the client to confirm the deductions.',
        'Filed and acknowledged. Copy shared with the client.',
        'Held up by one missing statement, chased twice this week.',
      ])),
    ],
  },
]


# --------------------------------------------------------------------------
# The professionals themselves
# --------------------------------------------------------------------------

PROFESSIONS = [
  {
    'key': 'fitness',
    'username': 'demo_fitness_pro',
    'professional_id': 'demo-fitness',
    'first_name': 'Aarav',
    'last_name': 'Kulkarni',
    'email': 'demo.fitness@reproot.demo',
    'professional_type': 'Personal Fitness Trainer',
    'headline': 'Strength and body-composition coaching for working professionals',
    'about': (
      'Aarav works with people who have demanding jobs and limited time, building strength and '
      'sustainable nutrition habits around a real schedule rather than an ideal one. Every client '
      'gets a written plan, weekly measurements, and an honest weekly review.'
    ),
    'specializations': 'Strength training, fat loss, habit coaching, beginner programming, injury-aware training',
    'years_experience': 9,
    'languages': 'English, Hindi, Marathi',
    'certification': ('Certified Strength and Conditioning Specialist', 'NSCA', 2018),
    'country': 'India',
    'state': 'Maharashtra',
    'gender': 'Male',
    'birth': (6, 1990),
    'currency': 'INR',
    'payment_methods': [
      ('upi', 'UPI', 'UPI - aarav@demoupi', {'upi_id': 'aarav@demoupi'}, 'Pay by UPI to aarav@demoupi and upload the confirmation screenshot.'),
      ('bank_transfer', 'Bank Transfer', 'Bank transfer (demo)', {'account_name': 'Aarav Kulkarni', 'account_number_last4': '4412', 'ifsc': 'DEMO0001234'}, 'Bank transfer using the details shared, then upload the receipt.'),
    ],
    'plan_price': 6500,
    'plan_name': 'Monthly coaching',
    'groups': [
      ('Strength Foundations', 'Beginners building movement quality, consistency, and baseline strength.'),
      ('Body Composition', 'Clients focused on fat loss, nutrition adherence, and weekly measurements.'),
      ('Return to Training', 'Clients coming back after a break or a managed injury.'),
    ],
    'templates': FITNESS_TEMPLATES,
    'resources': [
      ('Warm-Up and Mobility', ['Hips', 'Shoulders', 'Spine'], [
        ('Hips', 'Hip mobility flow', 'video_link', 'Ten minutes before every lower-body session.', 'https://www.youtube.com/watch?v=jj2AAH6jbHk'),
        ('Shoulders', 'Shoulder prep sequence', 'video_link', 'Activation work before pressing days.', 'https://www.youtube.com/watch?v=Vwn5hSf3WEg'),
        ('Spine', 'Thoracic rotation reset', 'text_note', 'Two sets of eight rotations per side, slow and controlled.', ''),
      ]),
      ('Technique Library', ['Squat', 'Hinge', 'Press'], [
        ('Squat', 'Goblet squat setup', 'video_link', 'Foot position, bracing, and depth.', 'https://www.youtube.com/watch?v=MeIiIdhvXT4'),
        ('Hinge', 'Romanian deadlift form', 'video_link', 'Hinge pattern for the posterior chain.', 'https://www.youtube.com/watch?v=2SHsk9AzdjA'),
        ('Press', 'Push-up progressions', 'video_link', 'Wall, incline, knee, and floor variations.', 'https://www.youtube.com/watch?v=IODxDxX7oi4'),
        ('Squat', 'Effort scale explained', 'text_note', 'RPE 6 leaves four reps in reserve; RPE 8 leaves two. Most sessions sit between the two.', ''),
      ]),
      ('Nutrition', ['Planning', 'Protein', 'Hydration'], [
        ('Planning', 'Building a balanced plate', 'text_note', 'Protein, produce, a smart carbohydrate, and a fat source at most meals.', ''),
        ('Protein', 'Protein anchors', 'text_note', 'Eggs, yoghurt, paneer, chicken, fish, lentils, tofu, or a shake at each meal.', ''),
        ('Hydration', 'Daily hydration plan', 'text_note', 'Half a litre on waking, then a glass with every meal.', ''),
        ('Planning', 'Sunday preparation checklist', 'text_note', 'Two proteins, two carbohydrates, three vegetables, one snack. Three days at a time.', ''),
      ]),
      ('Recovery and Mindset', ['Sleep', 'Stress', 'Consistency'], [
        ('Sleep', 'Sleep routine reset', 'text_note', 'Fixed wind-down time, dim screens 45 minutes before bed, caffeine before noon.', ''),
        ('Stress', 'Five-minute breathing drill', 'video_link', 'Use on high-stress days before training.', 'https://www.youtube.com/watch?v=inpok4MKVLM'),
        ('Consistency', 'The missed-session rule', 'text_note', 'Never miss twice. If a full session is impossible, do the ten-minute minimum and log it.', ''),
      ]),
    ],
    'clients': [
      ('Rohan', 'Mehta', 'Body Composition'), ('Sneha', 'Iyer', 'Strength Foundations'),
      ('Vikram', 'Desai', 'Body Composition'), ('Ananya', 'Rao', 'Strength Foundations'),
      ('Karthik', 'Nair', 'Return to Training'), ('Divya', 'Menon', 'Body Composition'),
      ('Arjun', 'Sharma', 'Strength Foundations'), ('Meera', 'Joshi', 'Return to Training'),
      ('Siddharth', 'Reddy', 'Body Composition'), ('Pooja', 'Bhat', 'Strength Foundations'),
    ],
    'chat': [
      ('professional', 'Welcome aboard. Your workout, nutrition, and weekly check-in templates are all set up.'),
      ('client', 'Thanks. Should I log the nutrition entry the same evening or the next morning?'),
      ('professional', 'Same evening while it is fresh. If you miss it, the next morning is fine.'),
      ('client', 'Got it. Also, my gym does not have a trap bar. Is there an alternative for the deadlift?'),
      ('professional', 'Yes, use the Romanian deadlift from the technique library at the same effort level.'),
      ('client', 'Perfect, will do that from tomorrow.'),
      ('professional', 'Measurements are due on Sunday. Same time of day as last week, before breakfast.'),
      ('client', 'Logged them just now. Waist is down another centimetre.'),
    ],
  },
  {
    'key': 'tutor',
    'username': 'demo_tutor_pro',
    'professional_id': 'demo-tutor',
    'first_name': 'Priya',
    'last_name': 'Raman',
    'email': 'demo.tutor@reproot.demo',
    'professional_type': 'Academic and Coding Tutor',
    'headline': 'Computer science tutoring and interview preparation',
    'about': (
      'Priya teaches programming fundamentals, data structures, and interview technique to students '
      'and career changers. Sessions are practice-heavy, and every assessment is scored and fed back '
      'so progress is visible rather than assumed.'
    ),
    'specializations': 'Python, data structures, algorithms, SQL, technical interview preparation',
    'years_experience': 7,
    'languages': 'English, Tamil, Hindi',
    'certification': ('MSc Computer Science', 'University of Edinburgh', 2016),
    'country': 'United States',
    'state': 'Texas',
    'gender': 'Female',
    'birth': (11, 1992),
    'currency': 'USD',
    'payment_methods': [
      ('zelle', 'Zelle', 'Zelle (demo)', {'zelle_handle': 'priya.tutor@reproot.demo'}, 'Send by Zelle to the address shown, then upload the confirmation.'),
      ('paypal_manual', 'PayPal', 'PayPal (manual transfer)', {'paypal_email': 'priya.tutor@reproot.demo'}, 'Send as friends and family, then upload the receipt.'),
    ],
    'plan_price': 320,
    'plan_name': 'Monthly tutoring block',
    'groups': [
      ('Placement Preparation', 'Final-year students preparing for campus and off-campus placements.'),
      ('Foundations', 'Students building programming fundamentals from the beginning.'),
      ('Career Changers', 'Working adults moving into software roles.'),
    ],
    'templates': TUTOR_TEMPLATES,
    'resources': [
      ('Fundamentals', ['Python', 'Logic', 'Practice'], [
        ('Python', 'Python basics recap', 'text_note', 'Types, loops, functions, and comprehensions in one page.', ''),
        ('Logic', 'How to trace a recursive call', 'text_note', 'Draw the stack. Every frame gets a line. Do not skip the base case.', ''),
        ('Practice', 'Daily practice set', 'text_note', 'Two easy problems and one medium, every weekday. Timed at thirty minutes.', ''),
      ]),
      ('Data Structures', ['Arrays', 'Trees', 'Graphs'], [
        ('Arrays', 'Two-pointer patterns', 'text_note', 'When the array is sorted, reach for two pointers before a nested loop.', ''),
        ('Trees', 'Traversal cheat sheet', 'text_note', 'Pre-order, in-order, post-order, and level-order with one example each.', ''),
        ('Graphs', 'BFS versus DFS', 'text_note', 'Shortest path in an unweighted graph is BFS. Connectivity and cycles are DFS.', ''),
      ]),
      ('Interview Preparation', ['Coding', 'Behavioural', 'Mock'], [
        ('Coding', 'Whiteboard checklist', 'text_note', 'Clarify, examples, approach, complexity, code, test. In that order.', ''),
        ('Behavioural', 'Six stories to prepare', 'text_note', 'Conflict, failure, leadership, deadline, ambiguity, proudest work.', ''),
        ('Mock', 'Recording your own answer', 'text_note', 'Record, watch it back once, note one fix. Do not re-record the same day.', ''),
      ]),
      ('Databases', ['SQL', 'Design', 'Practice'], [
        ('SQL', 'Join types explained', 'text_note', 'Inner, left, right, and full outer joins with a worked example.', ''),
        ('Design', 'Normalisation in practice', 'text_note', 'First, second, and third normal form using a single orders table.', ''),
        ('Practice', 'Query drills', 'text_note', 'Ten queries of increasing difficulty against the sample schema.', ''),
      ]),
    ],
    'clients': [
      ('Daniel', 'Okafor', 'Placement Preparation'), ('Emily', 'Zhang', 'Foundations'),
      ('Marcus', 'Bell', 'Career Changers'), ('Sofia', 'Alvarez', 'Placement Preparation'),
      ('Ravi', 'Krishnan', 'Foundations'), ('Hannah', 'Weber', 'Career Changers'),
      ('Tomas', 'Novak', 'Placement Preparation'), ('Grace', 'Adeyemi', 'Foundations'),
      ('Leo', 'Fontaine', 'Career Changers'), ('Aisha', 'Rahman', 'Placement Preparation'),
    ],
    'chat': [
      ('professional', 'Your study plan and the weekly assessment are both set up. Start with the recursion set.'),
      ('client', 'Thank you. Do I log the practice problems even if I could not finish them?'),
      ('professional', 'Especially then. Log what you tried and where you got stuck, that is the useful part.'),
      ('client', 'Makes sense. I finished four of five today, the last one on graphs beat me.'),
      ('professional', 'That is the right ratio. We will do graphs together in the next session.'),
      ('client', 'Also, is the mock interview still on for Thursday?'),
      ('professional', 'Yes, Thursday at six. Prepare two of the six stories beforehand.'),
    ],
  },
  {
    'key': 'career',
    'username': 'demo_career_pro',
    'professional_id': 'demo-career',
    'first_name': 'James',
    'last_name': 'Whitfield',
    'email': 'demo.career@reproot.demo',
    'professional_type': 'Career and Job Search Coach',
    'headline': 'Job search strategy, interview preparation, and career transitions',
    'about': (
      'James works with people in the middle of a job search or a career change. The work is practical: '
      'a tracked application pipeline, prepared interview answers, and a small number of weekly commitments '
      'that actually get reviewed.'
    ),
    'specializations': 'Job search strategy, CV and profile review, interview coaching, salary negotiation',
    'years_experience': 12,
    'languages': 'English',
    'certification': ('Certified Career Development Professional', 'NCDA', 2015),
    'country': 'United Kingdom',
    'state': 'Greater Manchester',
    'gender': 'Male',
    'birth': (3, 1984),
    'currency': 'USD',
    'payment_methods': [
      ('paypal_manual', 'PayPal', 'PayPal (manual transfer)', {'paypal_email': 'james.coach@reproot.demo'}, 'Send the fee by PayPal, then upload the receipt here.'),
      ('bank_transfer', 'Bank Transfer', 'Bank transfer (demo)', {'account_name': 'J Whitfield', 'account_number_last4': '8891'}, 'Bank transfer using the details shared in your welcome email.'),
    ],
    'plan_price': 450,
    'plan_name': 'Monthly coaching package',
    'groups': [
      ('Active Search', 'Clients applying now, with a live pipeline to review each week.'),
      ('Career Changers', 'Clients moving industry or function.'),
      ('Interview Intensive', 'Short engagements focused on an upcoming interview process.'),
    ],
    'templates': CAREER_TEMPLATES,
    'resources': [
      ('Applications', ['CV', 'Cover letters', 'Profiles'], [
        ('CV', 'One-page CV structure', 'text_note', 'Summary, experience with quantified impact, skills, education. Nothing else.', ''),
        ('Cover letters', 'The three-paragraph letter', 'text_note', 'Why them, why you, what you would do first. Under 250 words.', ''),
        ('Profiles', 'Profile headline formula', 'text_note', 'Role, specialism, and the outcome you produce. No adjectives.', ''),
      ]),
      ('Interviews', ['Behavioural', 'Technical', 'Questions'], [
        ('Behavioural', 'Structuring an answer', 'text_note', 'Situation, task, action, result. Spend most of the time on action.', ''),
        ('Technical', 'Talking through your work', 'text_note', 'Explain the decision, the alternative you rejected, and why.', ''),
        ('Questions', 'Questions worth asking', 'text_note', 'Ask about the first ninety days, how success is measured, and what is hard about the role.', ''),
      ]),
      ('Negotiation', ['Research', 'Scripts', 'Offers'], [
        ('Research', 'Finding the range', 'text_note', 'Three sources minimum, adjusted for location and company size.', ''),
        ('Scripts', 'The first number', 'text_note', 'Give a range with your target at the bottom of it, then stop talking.', ''),
        ('Offers', 'Comparing two offers', 'text_note', 'Compare total package, growth, manager, and commute. Weight them before you see the numbers.', ''),
      ]),
      ('Networking', ['Outreach', 'Follow-up', 'Events'], [
        ('Outreach', 'The cold message that works', 'text_note', 'Specific reference, one clear ask, easy to say no to. Four sentences.', ''),
        ('Follow-up', 'When to follow up', 'text_note', 'Once after a week, once after two. Then leave it.', ''),
        ('Events', 'Getting value from an event', 'text_note', 'Three conversations, not thirty. Follow up the same evening.', ''),
      ]),
    ],
    'clients': [
      ('Olivia', 'Grant', 'Active Search'), ('Nathan', 'Price', 'Career Changers'),
      ('Chloe', 'Barnes', 'Interview Intensive'), ('Ibrahim', 'Yusuf', 'Active Search'),
      ('Ella', 'Thompson', 'Career Changers'), ('Ryan', 'Doyle', 'Active Search'),
      ('Amara', 'Nwosu', 'Interview Intensive'), ('Felix', 'Hartmann', 'Career Changers'),
      ('Jasmine', 'Clarke', 'Active Search'), ('Owen', 'Fletcher', 'Interview Intensive'),
    ],
    'chat': [
      ('professional', 'Your application tracker is live. Log every application, including the ones you are unsure about.'),
      ('client', 'Will do. Do rejections still go in?'),
      ('professional', 'Yes. The pattern in rejections is usually where the real problem is.'),
      ('client', 'Fair. I had a screening call today that went better than expected.'),
      ('professional', 'Log it under the interview tracker with your preparation rating while it is fresh.'),
      ('client', 'Done. Rated preparation a four, the salary question caught me out though.'),
      ('professional', 'We will script that one on Thursday. It comes up every time.'),
    ],
  },
  {
    'key': 'sports',
    'username': 'demo_sports_pro',
    'professional_id': 'demo-sports',
    'first_name': 'Maria',
    'last_name': 'Santos',
    'email': 'demo.sports@reproot.demo',
    'professional_type': 'Sports Coach',
    'headline': 'Athlete development, performance testing, and match preparation',
    'about': (
      'Maria coaches club and academy athletes through structured training blocks, with performance '
      'testing every week and a readiness check before every session. Load is adjusted from what the '
      'athlete reports, not from the plan on paper.'
    ),
    'specializations': 'Speed and agility, strength for sport, return to play, match analysis',
    'years_experience': 11,
    'languages': 'English, Spanish, Portuguese',
    'certification': ('UEFA B Coaching Licence', 'Football Association', 2019),
    'country': 'India',
    'state': 'Karnataka',
    'gender': 'Female',
    'birth': (8, 1987),
    'currency': 'INR',
    'payment_methods': [
      ('upi', 'UPI', 'UPI - maria@demoupi', {'upi_id': 'maria@demoupi'}, 'Pay the monthly fee by UPI and upload the screenshot.'),
      ('cash', 'Cash', 'Cash at the ground', {}, 'Cash accepted at the ground on the first session of the month.'),
    ],
    'plan_price': 4500,
    'plan_name': 'Monthly squad fee',
    'groups': [
      ('Senior Squad', 'Competitive squad training four to five times a week.'),
      ('Development Squad', 'Younger athletes building technical foundations.'),
      ('Return to Play', 'Athletes working back from injury on a managed load.'),
    ],
    'templates': SPORTS_TEMPLATES,
    'resources': [
      ('Warm-Up', ['Activation', 'Speed', 'Mobility'], [
        ('Activation', 'Pre-session activation', 'text_note', 'Twelve minutes: glutes, hamstrings, calves, then two short accelerations.', ''),
        ('Speed', 'Sprint mechanics drill', 'video_link', 'Wall drills and A-skips before every speed session.', 'https://www.youtube.com/watch?v=Vwn5hSf3WEg'),
        ('Mobility', 'Ankle and hip prep', 'text_note', 'Two rounds, both sides, before any change-of-direction work.', ''),
      ]),
      ('Testing', ['Protocols', 'Targets', 'History'], [
        ('Protocols', 'How we test the 20m sprint', 'text_note', 'Same surface, same footwear, two attempts, best recorded.', ''),
        ('Targets', 'Squad benchmarks', 'text_note', 'The number that matters is your own previous result, not the squad average.', ''),
        ('History', 'Reading your trend', 'text_note', 'A single bad test is noise. Three in a row is a signal.', ''),
      ]),
      ('Recovery', ['Sleep', 'Nutrition', 'Load'], [
        ('Sleep', 'Sleep for athletes', 'text_note', 'Eight hours is training. Treat it like a session, not a luxury.', ''),
        ('Nutrition', 'Match-day eating', 'text_note', 'Main meal three hours before, small carbohydrate snack an hour before.', ''),
        ('Load', 'When to say you are not ready', 'text_note', 'Report it honestly. Adjusted load beats a missed month.', ''),
      ]),
      ('Match Preparation', ['Tactics', 'Set pieces', 'Review'], [
        ('Tactics', 'Pressing triggers', 'text_note', 'Backwards pass, poor first touch, or a receiver facing their own goal.', ''),
        ('Set pieces', 'Defending corners', 'text_note', 'Zonal in the six-yard box, man-marking beyond it. Same every match.', ''),
        ('Review', 'Watching your own footage', 'text_note', 'Two clips you did well, one to fix. Bring them to Monday.', ''),
      ]),
    ],
    'clients': [
      ('Aditya', 'Pillai', 'Senior Squad'), ('Neha', 'Fernandes', 'Development Squad'),
      ('Rahul', 'Verma', 'Senior Squad'), ('Ishita', 'Chatterjee', 'Return to Play'),
      ('Manav', 'Gupta', 'Development Squad'), ('Tara', 'Dsouza', 'Senior Squad'),
      ('Kabir', 'Singh', 'Return to Play'), ('Riya', 'Kapoor', 'Development Squad'),
      ('Aryan', 'Malhotra', 'Senior Squad'), ('Sana', 'Qureshi', 'Development Squad'),
    ],
    'chat': [
      ('professional', 'Readiness check-in goes in before every session, not after. It decides your load.'),
      ('client', 'Understood. Sunday I slept badly, should I still train?'),
      ('professional', 'Log it honestly and come in. We will keep it technical and drop the sprint work.'),
      ('client', 'That worked well, legs felt much better by the end.'),
      ('professional', 'Good. Testing is Thursday, same shoes and the same surface as last time.'),
      ('client', 'Will do. Sprint felt quicker last week even before the numbers.'),
    ],
  },
  {
    'key': 'consult',
    'username': 'demo_consult_pro',
    'professional_id': 'demo-consult',
    'first_name': 'Daniel',
    'last_name': 'Osei',
    'email': 'demo.consult@reproot.demo',
    'professional_type': 'Independent Consultant',
    'headline': 'Operations and business advisory for small and growing companies',
    'about': (
      'Daniel advises owner-managed businesses on operations, process, and the decisions that come with '
      'growth. Engagements are short and specific: an intake, a working session, and a written summary '
      'with the follow-up tracked to close.'
    ),
    'specializations': 'Operations review, process design, compliance readiness, contract review',
    'years_experience': 15,
    'languages': 'English, French',
    'certification': ('MBA', 'INSEAD', 2012),
    'country': 'United States',
    'state': 'Illinois',
    'gender': 'Male',
    'birth': (1, 1981),
    'currency': 'USD',
    'payment_methods': [
      ('bank_transfer', 'Bank Transfer', 'Bank transfer (demo)', {'account_name': 'D Osei Advisory', 'account_number_last4': '2207'}, 'Bank transfer on receipt of the invoice, then upload the confirmation.'),
      ('paypal_manual', 'PayPal', 'PayPal (manual transfer)', {'paypal_email': 'daniel.advisory@reproot.demo'}, 'PayPal accepted for one-off consultations.'),
    ],
    'plan_price': 900,
    'plan_name': 'Advisory retainer',
    'groups': [
      ('Retainer Clients', 'Ongoing advisory relationships reviewed monthly.'),
      ('Project Engagements', 'Fixed-scope pieces of work with a defined end.'),
      ('Initial Consultations', 'First conversations that have not yet become engagements.'),
    ],
    'templates': CONSULT_TEMPLATES,
    'resources': [
      ('Getting Started', ['Intake', 'Scope', 'Working together'], [
        ('Intake', 'What to prepare for the first session', 'text_note', 'The question you want answered, what you have tried, and who decides.', ''),
        ('Scope', 'How engagements are scoped', 'text_note', 'One outcome, one timeline, one price. Anything else becomes a second engagement.', ''),
        ('Working together', 'How we communicate', 'text_note', 'Everything of consequence is written down and lands in your portal.', ''),
      ]),
      ('Operations', ['Process', 'Metrics', 'Delegation'], [
        ('Process', 'Mapping a process honestly', 'text_note', 'Map what happens, not what is supposed to happen. The gap is the work.', ''),
        ('Metrics', 'Choosing three numbers', 'text_note', 'One for demand, one for delivery, one for cash. Review weekly.', ''),
        ('Delegation', 'What to hand over first', 'text_note', 'Whatever is frequent, documented, and low risk. In that order.', ''),
      ]),
      ('Compliance', ['Records', 'Contracts', 'Review'], [
        ('Records', 'Record-keeping baseline', 'text_note', 'What to keep, for how long, and where it lives.', ''),
        ('Contracts', 'Clauses worth reading twice', 'text_note', 'Termination, liability, payment terms, and change of scope.', ''),
        ('Review', 'Annual review checklist', 'text_note', 'Ten items, once a year, ninety minutes. It prevents most surprises.', ''),
      ]),
    ],
    'clients': [
      ('Helena', 'Bright', 'Retainer Clients'), ('Marcus', 'Adeleke', 'Project Engagements'),
      ('Yuki', 'Tanaka', 'Retainer Clients'), ('Paul', 'Girard', 'Initial Consultations'),
      ('Rebecca', 'Stone', 'Project Engagements'), ('Andres', 'Molina', 'Retainer Clients'),
      ('Fatima', 'Haddad', 'Initial Consultations'), ('Gregory', 'Lin', 'Project Engagements'),
      ('Nadia', 'Petrova', 'Retainer Clients'), ('Simon', 'Baptiste', 'Initial Consultations'),
    ],
    'chat': [
      ('professional', 'Your intake record and the summary from Tuesday are both in the portal.'),
      ('client', 'Read them, thank you. The second recommendation is the one we will struggle with.'),
      ('professional', 'Understood. Let us take that one in stages rather than all at once.'),
      ('client', 'That would help. Can we review it at the next session?'),
      ('professional', 'Yes, it is on the follow-up list with a date against it.'),
    ],
  },
  {
    'key': 'tax',
    'username': 'demo_tax_pro',
    'professional_id': 'demo-tax',
    'first_name': 'Sunita',
    'last_name': 'Agarwal',
    'email': 'demo.tax@reproot.demo',
    'professional_type': 'Tax and Financial Consultant',
    'headline': 'Tax filing, planning, and year-round advisory for individuals and small businesses',
    'about': (
      'Sunita handles filings and planning for individuals, freelancers, and small businesses. Every case '
      'runs through the same checklist so nothing is missed, and clients can see exactly which documents '
      'are still outstanding.'
    ),
    'specializations': 'Individual and business filing, tax planning, notice response, bookkeeping review',
    'years_experience': 13,
    'languages': 'English, Hindi, Gujarati',
    'certification': ('Chartered Accountant', 'ICAI', 2013),
    'country': 'India',
    'state': 'Gujarat',
    'gender': 'Female',
    'birth': (9, 1986),
    'currency': 'INR',
    'payment_methods': [
      ('upi', 'UPI', 'UPI - sunita@demoupi', {'upi_id': 'sunita@demoupi'}, 'Pay the fee by UPI and upload the confirmation.'),
      ('bank_transfer', 'Bank Transfer', 'Bank transfer (demo)', {'account_name': 'Sunita Agarwal', 'account_number_last4': '6673', 'ifsc': 'DEMO0004321'}, 'Bank transfer using the details on the invoice.'),
    ],
    'plan_price': 3500,
    'plan_name': 'Annual filing fee',
    'groups': [
      ('Individual Filing', 'Salaried and freelance individual returns.'),
      ('Business Filing', 'Small business and partnership returns.'),
      ('Advisory', 'Year-round planning clients.'),
    ],
    'templates': TAX_TEMPLATES,
    'resources': [
      ('Document Guides', ['Individuals', 'Business', 'Proofs'], [
        ('Individuals', 'What to send for an individual return', 'text_note', 'Income statements, interest certificates, investment proofs, and last year’s return.', ''),
        ('Business', 'What to send for a business return', 'text_note', 'Ledgers, bank statements, invoices raised, and expense records.', ''),
        ('Proofs', 'Photographing documents properly', 'text_note', 'Flat surface, all four corners visible, no shadow across the text.', ''),
      ]),
      ('Planning', ['Deductions', 'Timing', 'Records'], [
        ('Deductions', 'Deductions people forget', 'text_note', 'Professional fees, home office share, and interest paid on qualifying loans.', ''),
        ('Timing', 'Why the date matters', 'text_note', 'A decision made in March and the same decision in April can be a year apart for tax.', ''),
        ('Records', 'Keeping records year-round', 'text_note', 'One folder per year, four subfolders. Ten minutes a month beats a week in March.', ''),
      ]),
      ('Filing', ['Process', 'After filing', 'Notices'], [
        ('Process', 'How a filing runs', 'text_note', 'Collection, preparation, your review, then filing. You approve before anything is submitted.', ''),
        ('After filing', 'What to keep afterwards', 'text_note', 'The acknowledgement and the working file. Both for the statutory period.', ''),
        ('Notices', 'If you receive a notice', 'text_note', 'Do not reply directly. Send it over the same day and we will draft the response.', ''),
      ]),
    ],
    'clients': [
      ('Ramesh', 'Patel', 'Individual Filing'), ('Kavya', 'Shetty', 'Advisory'),
      ('Imran', 'Sheikh', 'Business Filing'), ('Lakshmi', 'Narayan', 'Individual Filing'),
      ('Gaurav', 'Trivedi', 'Business Filing'), ('Anjali', 'Deshpande', 'Advisory'),
      ('Nikhil', 'Jain', 'Individual Filing'), ('Farida', 'Contractor', 'Business Filing'),
      ('Suresh', 'Rana', 'Advisory'), ('Bhavna', 'Solanki', 'Individual Filing'),
    ],
    'chat': [
      ('professional', 'The document checklist is in your portal. Three items are still outstanding.'),
      ('client', 'I have uploaded two of them. The investment proof will take a few days.'),
      ('professional', 'That is fine, we have time. I will mark it as awaiting.'),
      ('client', 'Will the filing still be done before the deadline?'),
      ('professional', 'Comfortably, as long as the last proof arrives this month.'),
      ('client', 'Sent it this morning.'),
    ],
  },
]
