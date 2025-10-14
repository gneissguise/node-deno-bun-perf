// Node.js API server.

const express = require('express');
const { Pool } = require('pg');

// Increase the default listener limit to handle high concurrency from autocannon
require('events').EventEmitter.defaultMaxListeners = 275;

const app = express();
const PORT = 3000;

// --- Database Configuration (unified with other runtimes) ---
const connectionString = process.env.DATABASE_URL || 'postgres://quiz_user:quiz_password@localhost:5432/quiz_db';

const DEFAULT_POOL = 110;
const poolSize = (() => {
	try {
		const raw = process.env.DB_POOL || '';
		const p = parseInt(raw, 10);
		return Number.isInteger(p) && p > 0 ? p : DEFAULT_POOL;
	} catch {
		return DEFAULT_POOL;
	}
})();

const pool = new Pool({
	connectionString,
	max: poolSize,
	idleTimeoutMillis: 30000,
	connectionTimeoutMillis: 10000,
});

// Provide a tagged-template-compatible helper so code can use sql`...`
const sql = async function sqlTagged(strings, ...values) {
	if (!Array.isArray(strings)) {
		const text = String(strings);
		const res = await pool.query(text);
		return res.rows;
	}
	let text = '';
	const args = [];
	for (let i = 0; i < strings.length; i++) {
		text += strings[i];
		if (i < values.length) {
			args.push(values[i]);
			text += `$${args.length}`;
		}
	}
	const res = await pool.query(text, args);
	return res.rows;
};

// Middleware to parse JSON bodies
app.use(express.json());

// --- Database helper functions (use sql tagged-template) ---
const getQuestionsFromDb = async () => {
  try {
    const rows = await sql`
      SELECT q.id, q.question_text, json_agg(json_build_object('id', o.id, 'option_text', o.option_text)) as options
      FROM questions q
      JOIN options o ON q.id = o.question_id
      GROUP BY q.id
      ORDER BY q.id;
    `;
    return rows;
  } catch (err) {
    console.error('getQuestionsFromDb error:', err && err.message ? err.message : err);
    throw err;
  }
};

const getQuestionByIdFromDb = async (id) => {
  try {
    const rows = await sql`
      SELECT q.id, q.question_text, json_agg(json_build_object('id', o.id, 'option_text', o.option_text)) as options
      FROM questions q
      JOIN options o ON q.id = o.question_id
      WHERE q.id = ${id}
      GROUP BY q.id;
    `;
    return rows ? rows[0] : undefined;
  } catch (err) {
    console.error('getQuestionByIdFromDb error:', err && err.message ? err.message : err);
    throw err;
  }
};

const saveAnswerToDb = async (questionId, optionId) => {
  try {
    await sql`
      INSERT INTO answers (question_id, selected_option_id)
      VALUES (${questionId}, ${optionId})
    `;
  } catch (err) {
    console.error('saveAnswerToDb error:', err && err.message ? err.message : err);
    throw err;
  }
};

// --- API Endpoints ---

// /healthcheck: keep it fast and DB-free
app.get('/healthcheck', (req, res) => {
	res.sendStatus(200);
});

app.get('/questions', async (req, res) => {
  try {
    const questions = await getQuestionsFromDb();
    res.json(questions);
  } catch (error) {
    res.status(500).send('Internal Server Error');
  }
});

app.get('/questions/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).send('Invalid question ID.');
    }
    const question = await getQuestionByIdFromDb(id);
    if (question) {
      res.json(question);
    } else {
      res.status(404).send('Question not found.');
    }
  } catch (error) {
    res.status(500).send('Internal Server Error');
  }
});

app.post('/answers', async (req, res) => {
  try {
    const { questionId, optionId } = req.body;
    if (!questionId || !optionId) {
      return res.status(400).send('Missing questionId or optionId');
    }
    await saveAnswerToDb(questionId, optionId);
    res.status(201).send('Answer saved');
  } catch (error) {
    res.status(500).send('Internal Server Error');
  }
});

// --- Wait for DB, clear answers, start server (unchanged API surface) ---
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitForDb(maxAttempts = 20, delayMs = 1500) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const client = await pool.connect();
      client.release();
      console.log(`Connected to DB on attempt ${attempt}`);
      return;
    } catch (err) {
      console.warn(`DB not ready (attempt ${attempt}/${maxAttempts}): ${err.message || err}`);
      if (attempt === maxAttempts) throw err;
      await sleep(delayMs);
    }
  }
}

async function init() {
  try {
    await waitForDb();
    try {
      await sql`TRUNCATE TABLE answers`;
      console.log('Answers table cleared.');
    } catch (err) {
      console.warn('Failed to truncate answers table (continuing):', err.message || err);
    }

    app.listen(PORT, () => {
      console.log(`Node.js Express server running on http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('Failed to initialize server:', err);
    process.exit(1);
  }
}

init();

// --- Add: global error handlers to surface startup failures ---
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
  // allow process to exit after logging if it's a fatal error
});

