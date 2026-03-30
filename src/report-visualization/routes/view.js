const express = require('express');
const router = express.Router();
const reportService = require('../services/reportService');

/**
 * @route GET /reports/:id/view
 * @desc 渲染报告的 HTML 视图
 */
router.get('/:id/view', (req, res) => {
  try {
    const report = reportService.getById(req.params.id);
    if (!report) {
      return res.status(404).send('<h1>404 - Report Not Found</h1>');
    }
    
    // 直接返回已生成的 HTML 字符串
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(report.html);
  } catch (error) {
    console.error(error);
    res.status(500).send('<h1>500 - Internal Server Error</h1>');
  }
});

module.exports = router;
