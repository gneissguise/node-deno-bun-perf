// Bun API server.

const PORT = 3002;

let sql;
let usedDriver = null;

// Pool size parsing (unchanged logic)
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

// --- Database Configuration (Using a Connection String for Explicitness) ---
const connectionString = 'postgres://quiz_user:quiz_password@localhost:5432/quiz_db';

/* New driver selection:
   - Try node-postgres ("pg") first (stable).
   - If not available, fall back to postgres.js (bun-native).
   - Provide a tagged-template-compatible helper in both cases so existing sql`...` usage works.
*/
try {
	// Try node-postgres (stable in many setups)
	const pgModule = await import('pg');
	const { Pool } = pgModule;
	const pgPool = new Pool({
		connectionString,
		max: poolSize,
		idleTimeoutMillis: 30000,
		connectionTimeoutMillis: 10000,
	});

	// tagged-template helper compatible with sql`...`
	sql = async function sqlTagged(strings, ...values) {
		// called as sql('plain sql string')
		if (!Array.isArray(strings)) {
			const text = String(strings);
			const res = await pgPool.query(text);
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
		const res = await pgPool.query(text, args);
		return res.rows;
	};

	// Simple wait-for-db using pgPool.connect
	async function waitForDbPg(maxAttempts = 20, delayMs = 1500) {
		for (let i = 1; i <= maxAttempts; i++) {
			try {
				const client = await pgPool.connect();
				client.release();
				console.log(`Bun(pg): connected to DB on attempt ${i}`);
				return;
			} catch (err) {
				console.warn(`Bun(pg): DB not ready (attempt ${i}/${maxAttempts}): ${err.message || err}`);
				if (i === maxAttempts) throw err;
				await new Promise((r) => setTimeout(r, delayMs));
			}
		}
	}
	// export wait helper for later use
	var waitForDbBun = waitForDbPg;

	usedDriver = 'pg';
	console.log(`Bun: using node-postgres "pg" driver (pool=${poolSize})`);
} catch (errPg) {
	// Fallback to postgres.js (bun-native)
	try {
		const postgresModule = await import('postgres');
		const postgres = postgresModule.default ?? postgresModule;
		// Use postgres.js without additional per-query wrappers
		sql = postgres(connectionString, {
			max: poolSize,
			// postgres.js expects ms values for these options
			idle_timeout: 30000,
			connect_timeout: 10000,
		});
		usedDriver = 'postgres';
		console.log(`Bun: using postgres.js driver (pool=${poolSize})`);

		// wait helper for postgres.js
		var waitForDbBun = async function (maxAttempts = 20, delayMs = 1500) {
			for (let i = 1; i <= maxAttempts; i++) {
				try {
					await sql`SELECT 1`;
					console.log(`Bun(postgres): connected to DB on attempt ${i}`);
					return;
				} catch (err) {
					console.warn(`Bun(postgres): DB not ready (attempt ${i}/${maxAttempts}): ${err.message || err}`);
					if (i === maxAttempts) throw err;
					await new Promise((r) => setTimeout(r, delayMs));
				}
			}
		};
	} catch (errPgJs) {
		console.error('Bun: no supported postgres driver found. Install "pg" (recommended) or "postgres".');
		console.error('pg error:', errPg);
		console.error('postgres.js error:', errPgJs);
		process.exit(1);
	}
}

// --- Database Functions ---

async function getQuestionsFromDb() {
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
}

async function getQuestionByIdFromDb(id) {
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
}

async function saveAnswerToDb(questionId, optionId) {
	try {
		await sql`
			INSERT INTO answers (question_id, selected_option_id)
			VALUES (${questionId}, ${optionId})
		`;
	} catch (err) {
		console.error('saveAnswerToDb error:', err && err.message ? err.message : err);
		throw err;
	}
}

// --- Add: DB-wait helper for Bun (was set above) ---
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- Start-up: wait for DB, clear answers, then start the server ---
(async () => {
	try {
		await waitForDbBun();
		try {
			await sql`TRUNCATE TABLE answers`;
			console.log('Answers table cleared.');
		} catch (err) {
			console.warn('Bun: failed to truncate answers table (continuing):', err.message || err);
		}

		console.log(`Bun server running on http://localhost:${PORT}`);
		Bun.serve({
			port: PORT,
			async fetch(req) {
				const url = new URL(req.url);
				const path = url.pathname;
				const method = req.method;

				// Health check for benchmark script
				if (path === '/healthcheck') {
					return new Response('OK', { status: 200 });
				}

				// Heavy Read
				if (method === 'GET' && path === '/questions') {
					try {
						const questions = await getQuestionsFromDb();
						return new Response(JSON.stringify(questions), {
							headers: { 'Content-Type': 'application/json' },
						});
					} catch (error) {
						console.error(error);
						return new Response('Internal Server Error', { status: 500 });
					}
				}

				// Random Read
				const questionMatch = path.match(/^\/questions\/(\d+)$/);
				if (method === 'GET' && questionMatch) {
					try {
						const id = parseInt(questionMatch[1], 10);
						const question = await getQuestionByIdFromDb(id);
						if (question) {
							return new Response(JSON.stringify(question), {
								headers: { 'Content-Type': 'application/json' },
							});
						} else {
							return new Response('Not Found', { status: 404 });
						}
					} catch (error) {
						console.error(error);
						return new Response('Internal Server Error', { status: 500 });
					}
				}

				// Random Write
				if (method === 'POST' && path === '/answers') {
					try {
						const body = await req.json();
						await saveAnswerToDb(body.questionId, body.optionId);
						return new Response('Answer saved', { status: 201 });
					} catch (error) {
						console.error(error);
						return new Response('Internal Server Error', { status: 500 });
					}
				}

				return new Response('Not Found', { status: 404 });
			},
		});
	} catch (err) {
		console.error('Bun server failed to start:', err);
		process.exit(1);
	}
})();

