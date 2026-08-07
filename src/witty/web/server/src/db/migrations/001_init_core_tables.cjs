/**
 * 初始建表（对应 02 §5.1 / 03 §3.3）。跨方言通用：
 * - 主键/UUID 用 varchar(36)，不依赖具体自增语义
 * - 时间戳统一 bigInteger（epoch ms），规避 SQLite/MySQL 时间类型差异
 * - 布尔以整型表达；不使用任一方言独有 SQL
 * 凭据无持久化表（仅内存密文驻留，BC-004）。
 */

exports.up = async function up(knex) {
  await knex.schema.createTable("users", (t) => {
    t.string("id", 36).primary();
    t.string("external_subject", 255).notNullable();
    t.string("display_name", 128);
    t.bigInteger("created_at").notNullable();
    t.unique(["external_subject"]);
  });

  await knex.schema.createTable("tasks", (t) => {
    t.string("id", 36).primary();
    t.string("owner_id", 36).notNullable().references("id").inTable("users");
    t.text("title").notNullable(); // 故障现象
    t.text("fault_time").notNullable(); // 自由文本
    t.string("mode", 16).notNullable(); // online | offline
    t.string("status", 16).notNullable(); // queued|running|succeeded|failed|canceled
    t.integer("progress").notNullable().defaultTo(0);
    t.string("current_stage", 32);
    t.text("fail_reason");
    t.bigInteger("created_at").notNullable();
    t.bigInteger("updated_at").notNullable();
    t.bigInteger("expire_at").notNullable();
    t.index(["owner_id"]);
    t.index(["status"]);
  });

  await knex.schema.createTable("online_targets", (t) => {
    t.string("task_id", 36).primary().references("id").inTable("tasks").onDelete("CASCADE");
    t.string("host_ip", 255).notNullable();
    t.string("ssh_user", 128).notNullable();
    t.integer("ssh_port").notNullable().defaultTo(22);
    // 不含密码：密码仅内存密文驻留，不落本表（BC-004 / DC-006）
  });

  await knex.schema.createTable("offline_uploads", (t) => {
    t.string("id", 36).primary();
    t.string("task_id", 36).references("id").inTable("tasks").onDelete("CASCADE");
    t.string("filename", 512).notNullable();
    t.text("stored_path").notNullable();
    t.bigInteger("size").notNullable().defaultTo(0);
    t.bigInteger("uploaded_at").notNullable();
    t.index(["task_id"]);
  });

  await knex.schema.createTable("executions", (t) => {
    t.string("id", 36).primary();
    t.string("task_id", 36).notNullable().references("id").inTable("tasks").onDelete("CASCADE");
    t.integer("attempt_no").notNullable().defaultTo(1);
    t.bigInteger("started_at");
    t.bigInteger("ended_at");
    t.string("exit_reason", 64);
    t.index(["task_id"]);
  });

  await knex.schema.createTable("log_chunks", (t) => {
    t.increments("id").primary();
    t.string("execution_id", 36).notNullable().references("id").inTable("executions").onDelete("CASCADE");
    t.integer("seq").notNullable();
    t.bigInteger("ts").notNullable();
    t.text("text").notNullable(); // 已脱敏
    t.index(["execution_id", "seq"]);
  });

  await knex.schema.createTable("reports", (t) => {
    t.string("id", 36).primary();
    t.string("task_id", 36).notNullable().references("id").inTable("tasks").onDelete("CASCADE");
    t.string("report_no", 64);
    t.string("fault_level", 128);
    t.text("html_path");
    t.text("md_path");
    t.text("report_json"); // 已脱敏的结构化报告
    t.bigInteger("created_at").notNullable();
    t.unique(["task_id"]);
  });

  await knex.schema.createTable("ratings", (t) => {
    t.string("task_id", 36).primary().references("id").inTable("tasks").onDelete("CASCADE");
    t.integer("stars").notNullable(); // 1..5
    t.text("note");
    t.bigInteger("updated_at").notNullable();
  });
};

exports.down = async function down(knex) {
  await knex.schema.dropTableIfExists("ratings");
  await knex.schema.dropTableIfExists("reports");
  await knex.schema.dropTableIfExists("log_chunks");
  await knex.schema.dropTableIfExists("executions");
  await knex.schema.dropTableIfExists("offline_uploads");
  await knex.schema.dropTableIfExists("online_targets");
  await knex.schema.dropTableIfExists("tasks");
  await knex.schema.dropTableIfExists("users");
};
