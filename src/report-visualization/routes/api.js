const express = require('express');
const router = express.Router();
const reportService = require('../services/reportService');

/**
 * @route POST /api/reports
 * @desc 接收 Markdown 报告，存入数据库并生成 HTML
 */
router.post('/', (req, res) => {
  try {
    const { title, markdown, type, severity } = req.body;
    
    if (!markdown) {
      return res.status(400).json({ error: 'markdown content is required' });
    }

    const report = reportService.create({
      title: title || '未命名诊断报告',
      markdown,
      type,
      severity
    });

    res.status(201).json({
      success: true,
      data: {
        id: report.id,
        url: `/reports/${report.id}/view`
      }
    });
  } catch (error) {
    console.error('Error creating report:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * @route GET /api/reports
 * @desc 获取报告列表
 */
router.get('/', (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    
    const result = reportService.getList(page, limit);
    res.json({ success: true, data: result });
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * @route GET /api/reports/:id
 * @desc 获取单篇报告详情（JSON，含原始 MD）
 */
router.get('/:id', (req, res) => {
  try {
    const report = reportService.getById(req.params.id);
    if (!report) {
      return res.status(404).json({ error: 'Report not found' });
    }
    res.json({ success: true, data: report });
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
