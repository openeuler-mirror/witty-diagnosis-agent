const db = require('../config/db');
const { nanoid } = require('nanoid');
const markdownService = require('./markdownService');

class ReportService {
  /**
   * 创建新报告
   * @param {Object} data
   * @returns {Object} 报告对象
   */
  create(data) {
    const id = nanoid(10);
    const { title, markdown, type = 'diagnosis', severity = 'info' } = data;
    
    // 生成 HTML
    const html = markdownService.toHtml(markdown, title);

    const stmt = db.prepare(`
      INSERT INTO reports (id, title, markdown, html, type, severity)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    
    stmt.run(id, title, markdown, html, type, severity);
    
    return this.getById(id);
  }

  /**
   * 获取报告详情
   * @param {string} id 
   */
  getById(id) {
    return db.prepare('SELECT * FROM reports WHERE id = ?').get(id);
  }

  /**
   * 获取报告列表（分页）
   */
  getList(page = 1, limit = 10) {
    const offset = (page - 1) * limit;
    
    const items = db.prepare(`
      SELECT id, title, type, severity, created_at 
      FROM reports 
      ORDER BY created_at DESC 
      LIMIT ? OFFSET ?
    `).all(limit, offset);
    
    const total = db.prepare('SELECT count(*) as count FROM reports').get().count;
    
    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit)
    };
  }
}

module.exports = new ReportService();
