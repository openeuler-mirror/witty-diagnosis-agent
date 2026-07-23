/**
 * 已知问题对话查询（QA）模块建表（对应 02 §5.1 / 03 §3.3）。纯新增两表，沿用 init 迁移风格：
 * - UUID 主键 varchar(36)，epoch ms 时间戳 bigInteger，级联删除
 * - JSON 快照字段统一用 text（sqlite 无 json 列；mysql 亦兼容），由应用层 JSON 序列化
 * - owner 隔离落 qa_sessions.owner_id；qa_messages 经 session_id 间接归属
 * 跨方言（SQLite/MySQL）通用，不使用任一方言独有 SQL。
 */

exports.up = async function up(knex) {
  await knex.schema.createTable("qa_sessions", (t) => {
    t.string("id", 36).primary();
    t.string("owner_id", 36).notNullable().references("id").inTable("users");
    t.text("title").notNullable(); // 由首条问题生成/可改
    t.string("oc_session_id", 64); // 绑定的 opencode sessionId（可失效重建，可空）
    t.string("kb_id", 64); // 本期单库，预留扩展（BC-007）
    t.bigInteger("created_at").notNullable();
    t.bigInteger("updated_at").notNullable();
    t.index(["owner_id"]);
  });

  await knex.schema.createTable("qa_messages", (t) => {
    t.string("id", 36).primary();
    t.string("session_id", 36).notNullable().references("id").inTable("qa_sessions").onDelete("CASCADE");
    t.string("role", 16).notNullable(); // user | assistant
    t.string("status", 16); // generating|done|aborted|failed（assistant）
    t.text("text"); // 已脱敏正文
    t.text("retrieval"); // {low[],high[]} JSON 快照
    t.text("citations"); // sources[] JSON 快照
    t.text("graph"); // {nodes[],edges[]} JSON 快照
    t.text("followups"); // 建议追问 JSON 快照（可空）
    t.string("feedback", 16); // useful|inaccurate|null（FR-008 质量回流）
    t.bigInteger("created_at").notNullable();
    t.index(["session_id", "created_at"]);
  });
};

exports.down = async function down(knex) {
  await knex.schema.dropTableIfExists("qa_messages");
  await knex.schema.dropTableIfExists("qa_sessions");
};
