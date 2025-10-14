-- Drop tables if they exist to ensure a clean slate
DROP TABLE IF EXISTS answers;
DROP TABLE IF EXISTS options;
DROP TABLE IF EXISTS questions;

-- Create the questions table
CREATE TABLE questions (
    id SERIAL PRIMARY KEY,
    question_text VARCHAR(255) NOT NULL
);

-- Create the options table
CREATE TABLE options (
    id SERIAL PRIMARY KEY,
    question_id INTEGER NOT NULL REFERENCES questions(id),
    option_text VARCHAR(255) NOT NULL
);

-- Create the answers table
-- CORRECTED: The column is named selected_option_id for clarity.
CREATE TABLE answers (
    id SERIAL PRIMARY KEY,
    question_id INTEGER NOT NULL REFERENCES questions(id),
    selected_option_id INTEGER NOT NULL REFERENCES options(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert 50 questions
INSERT INTO questions (question_text) VALUES
('What is the capital of France?'),
('Which planet is known as the Red Planet?'),
('What is the largest mammal in the world?'),
('In what year did the Titanic sink?'),
('Who wrote "To Kill a Mockingbird"?'),
('What is the chemical symbol for gold?'),
('How many continents are there?'),
('What is the main ingredient in guacamole?'),
('Who painted the Mona Lisa?'),
('What is the hardest natural substance on Earth?'),
('Which is the longest river in the world?'),
('What does "CPU" stand for?'),
('Who discovered penicillin?'),
('What is the capital of Japan?'),
('Which is the only mammal capable of sustained flight?'),
('What is the square root of 64?'),
('What is the largest ocean on Earth?'),
('Who invented the light bulb?'),
('What is the smallest prime number?'),
('How many players are on a soccer team?'),
('What is the currency of the United Kingdom?'),
('What is the boiling point of water in Celsius?'),
('Who was the first person to step on the moon?'),
('What is the primary language spoken in Brazil?'),
('Which element is most abundant in the Earth''s atmosphere?'),
('What type of animal is a Komodo dragon?'),
('What is the main programming language used for Android app development?'),
('How many strings does a standard violin have?'),
('Which country is known as the Land of the Rising Sun?'),
('What is the largest desert in the world?'),
('Who is credited with the theory of relativity?'),
('Which is the smallest continent by land area?'),
('What is the name of the galaxy that contains our Solar System?'),
('What does "HTTP" stand for?'),
('Which artist cut off his own ear?'),
('What is the main component of the sun?'),
('How many bones are in the adult human body?'),
('What is the capital of Canada?'),
('In which sport would you perform a slam dunk?'),
('What is the largest planet in our solar system?'),
('What is the study of earthquakes called?'),
('Who wrote the "Harry Potter" series?'),
('What is the freezing point of water in Fahrenheit?'),
('Which ocean is the Bermuda Triangle located in?'),
('What is the most spoken language in the world?'),
('What is the speed of light?'),
('What is the chemical formula for water?'),
('How many sides does a hexagon have?'),
('What is the fear of spiders called?'),
('Who was the first President of the United States?');

-- Insert options for all 50 questions
INSERT INTO options (question_id, option_text) VALUES
(1, 'Berlin'), (1, 'Madrid'), (1, 'Paris'), (1, 'Rome'),
(2, 'Earth'), (2, 'Mars'), (2, 'Jupiter'), (2, 'Venus'),
(3, 'Elephant'), (3, 'Blue Whale'), (3, 'Giraffe'), (3, 'Great White Shark'),
(4, '1905'), (4, '1912'), (4, '1918'), (4, '1923'),
(5, 'Harper Lee'), (5, 'J.K. Rowling'), (5, 'F. Scott Fitzgerald'), (5, 'Ernest Hemingway'),
(6, 'Ag'), (6, 'Go'), (6, 'Au'), (6, 'Ge'),
(7, '5'), (7, '6'), (7, '7'), (7, '8'),
(8, 'Tomato'), (8, 'Avocado'), (8, 'Onion'), (8, 'Lime'),
(9, 'Vincent van Gogh'), (9, 'Pablo Picasso'), (9, 'Leonardo da Vinci'), (9, 'Claude Monet'),
(10, 'Gold'), (10, 'Iron'), (10, 'Diamond'), (10, 'Quartz'),
(11, 'Amazon'), (11, 'Nile'), (11, 'Yangtze'), (11, 'Mississippi'),
(12, 'Central Processing Unit'), (12, 'Computer Personal Unit'), (12, 'Central Process Unit'), (12, 'Computer Processing Unit'),
(13, 'Marie Curie'), (13, 'Alexander Fleming'), (13, 'Isaac Newton'), (13, 'Albert Einstein'),
(14, 'Beijing'), (14, 'Seoul'), (14, 'Tokyo'), (14, 'Bangkok'),
(15, 'Flying Squirrel'), (15, 'Bat'), (15, 'Ostrich'), (15, 'Penguin'),
(16, '6'), (16, '7'), (16, '8'), (16, '9'),
(17, 'Atlantic'), (17, 'Indian'), (17, 'Arctic'), (17, 'Pacific'),
(18, 'Nikola Tesla'), (18, 'Thomas Edison'), (18, 'Alexander Graham Bell'), (18, 'Benjamin Franklin'),
(19, '0'), (19, '1'), (19, '2'), (19, '3'),
(20, '9'), (20, '10'), (20, '11'), (20, '12'),
(21, 'Euro'), (21, 'Pound Sterling'), (21, 'Dollar'), (21, 'Yen'),
(22, '90°C'), (22, '100°C'), (22, '110°C'), (22, '120°C'),
(23, 'Buzz Aldrin'), (23, 'Yuri Gagarin'), (23, 'Neil Armstrong'), (23, 'Michael Collins'),
(24, 'Spanish'), (24, 'Portuguese'), (24, 'English'), (24, 'French'),
(25, 'Oxygen'), (25, 'Carbon Dioxide'), (25, 'Nitrogen'), (25, 'Argon'),
(26, 'Mammal'), (26, 'Reptile'), (26, 'Bird'), (26, 'Amphibian'),
(27, 'Swift'), (27, 'Kotlin'), (27, 'C#'), (27, 'Java (historically)'),
(28, '4'), (28, '5'), (28, '6'), (28, '7'),
(29, 'China'), (29, 'South Korea'), (29, 'Japan'), (29, 'Thailand'),
(30, 'Sahara'), (30, 'Gobi'), (30, 'Arabian'), (30, 'Antarctic Polar Desert'),
(31, 'Isaac Newton'), (31, 'Galileo Galilei'), (31, 'Albert Einstein'), (31, 'Stephen Hawking'),
(32, 'Europe'), (32, 'Antarctica'), (32, 'South America'), (32, 'Australia'),
(33, 'Andromeda'), (33, 'Milky Way'), (33, 'Triangulum'), (33, 'Whirlpool'),
(34, 'HyperText Transfer Protocol'), (34, 'HyperText Transmission Protocol'), (34, 'HyperText Transfer Page'), (34, 'HyperText Transmission Page'),
(35, 'Pablo Picasso'), (35, 'Vincent van Gogh'), (35, 'Salvador Dalí'), (35, 'Claude Monet'),
(36, 'Oxygen'), (36, 'Hydrogen'), (36, 'Helium'), (36, 'Carbon'),
(37, '206'), (37, '216'), (37, '196'), (37, '226'),
(38, 'Toronto'), (38, 'Vancouver'), (38, 'Ottawa'), (38, 'Montreal'),
(39, 'Volleyball'), (39, 'Basketball'), (39, 'Tennis'), (39, 'Badminton'),
(40, 'Saturn'), (40, 'Jupiter'), (40, 'Neptune'), (40, 'Uranus'),
(41, 'Geology'), (41, 'Seismology'), (41, 'Meteorology'), (41, 'Volcanology'),
(42, 'J.R.R. Tolkien'), (42, 'George R.R. Martin'), (42, 'J.K. Rowling'), (42, 'C.S. Lewis'),
(43, '0°F'), (43, '32°F'), (43, '45°F'), (43, '10°F'),
(44, 'Pacific'), (44, 'Indian'), (44, 'Atlantic'), (44, 'Arctic'),
(45, 'Spanish'), (45, 'Mandarin Chinese'), (45, 'English'), (45, 'Hindi'),
(46, '299,792 km/s'), (46, '150,000 km/s'), (46, '500,000 km/s'), (46, '1,000,000 km/s'),
(47, 'CO2'), (47, 'H2O'), (47, 'O2'), (47, 'NaCl'),
(48, '5'), (48, '6'), (48, '7'), (48, '8'),
(49, 'Agoraphobia'), (49, 'Claustrophobia'), (49, 'Arachnophobia'), (49, 'Acrophobia'),
(50, 'Abraham Lincoln'), (50, 'Thomas Jefferson'), (50, 'George Washington'), (50, 'John Adams');

