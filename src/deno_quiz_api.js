// Deno API server.

import { Pool } from "https://deno.land/x/postgres@v0.17.0/mod.ts";

const PORT = 3001;

// Parse DB pool size from env (Deno: Deno.env.get)
const DEFAULT_POOL = 110;
const rawPool = (typeof Deno !== 'undefined' && Deno.env.get) ? Deno.env.get('DB_POOL') : undefined;
const poolSize = (() => {
	try {
		const p = rawPool ? Number.parseInt(rawPool, 10) : NaN;
		return Number.isInteger(p) && p > 0 ? p : DEFAULT_POOL;
	} catch {
		return DEFAULT_POOL;
	}
})();

// --- Database Configuration (Using a Connection String) ---
// Use the same 'postgres://' style used across runtimes
const connectionString = Deno.env.get('DATABASE_URL') || 'postgres://quiz_user:quiz_password@localhost:5432/quiz_db';
const pool = new Pool(connectionString, poolSize, true);

// --- Database Functions ---

const getQuestionsFromDb = async () => {
  const client = await pool.connect();
  try {
    const result = await client.queryObject(`
      SELECT q.id, q.question_text, json_agg(json_build_object('id', o.id, 'option_text', o.option_text)) as options
      FROM questions q
      JOIN options o ON q.id = o.question_id
      GROUP BY q.id
      ORDER BY q.id;
    `);
    return result.rows;
  } finally {
    client.release();
  }
};

const getQuestionByIdFromDb = async (id) => {
  const client = await pool.connect();
  try {
    const result = await client.queryObject({
      text: `
        SELECT q.id, q.question_text, json_agg(json_build_object('id', o.id, 'option_text', o.option_text)) as options
        FROM questions q
        JOIN options o ON q.id = o.question_id
        WHERE q.id = $1
        GROUP BY q.id;
      `,
      args: [id],
    });
    return result.rows[0];
  } finally {
    client.release();
  }
};

const saveAnswerToDb = async (questionId, optionId) => {
  const client = await pool.connect();
  try {
    await client.queryObject({
      text: 'INSERT INTO answers (question_id, selected_option_id) VALUES ($1, $2)',
      args: [questionId, optionId]
    });
  } finally {
    client.release();
  }
};


// --- Main Server Logic ---

const handler = async (req) => {
  const url = new URL(req.url);
  const path = url.pathname;
  const method = req.method;

  // Health check for benchmark script
  if (path === '/healthcheck') {
    return new Response("OK", { status: 200 });
  }

  // Heavy Read
  if (method === 'GET' && path === '/questions') {
    try {
      const questions = await getQuestionsFromDb();
      return new Response(JSON.stringify(questions), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch (e) {
      console.error(e);
      return new Response("Internal Server Error", { status: 500 });
    }
  }

  // Random Read (using URLPattern for robust matching)
  const questionPattern = new URLPattern({ pathname: '/questions/:id' });
  const questionMatch = questionPattern.exec(req.url);
  if (method === 'GET' && questionMatch) {
    try {
      const id = parseInt(questionMatch.pathname.groups.id, 10);
      if (isNaN(id)) {
        return new Response("Invalid ID", { status: 400 });
      }
      const question = await getQuestionByIdFromDb(id);
      if (question) {
        return new Response(JSON.stringify(question), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      } else {
        return new Response("Not Found", { status: 404 });
      }
    } catch (e) {
      console.error(e);
      return new Response("Internal Server Error", { status: 500 });
    }
  }

  // Random Write
  if (method === 'POST' && path === '/answers') {
    try {
      const body = await req.json();
      if (!body.questionId || !body.optionId) {
        return new Response("Missing body params", { status: 400 });
      }
      await saveAnswerToDb(body.questionId, body.optionId);
      return new Response("Answer saved", { status: 201 });
    } catch (e) {
      console.error(e);
      return new Response("Internal Server Error", { status: 500 });
    }
  }

  return new Response("Not Found", { status: 404 });
};


// --- Server Startup ---
const clearAnswersTable = async () => {
  try {
    const client = await pool.connect();
    try {
      await client.queryObject('TRUNCATE TABLE answers');
      console.log('Answers table cleared.');
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Error clearing answers table:', error);
  }
};

// --- Add: DB-wait helper for Deno ---
async function waitForDbDeno(maxAttempts = 20, delayMs = 1500) {
  for (let i = 1; i <= maxAttempts; i++) {
    try {
      const client = await pool.connect();
      client.release();
      console.log(`Deno: connected to DB on attempt ${i}`);
      return;
    } catch (err) {
      console.warn(`Deno: DB not ready (attempt ${i}/${maxAttempts}): ${err.message || err}`);
      if (i === maxAttempts) throw err;
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
}

// --- Use DB wait before clearing answers and starting server ---
console.log(`Deno server preparing on http://localhost:${PORT}`);
try {
  await waitForDbDeno();
  await clearAnswersTable();
  Deno.serve({ port: PORT, handler });
} catch (err) {
  console.error('Deno server failed to start:', err);
  Deno.exit(1);
}

