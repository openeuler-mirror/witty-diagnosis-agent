require('dotenv').config();
const express = require('express');
const path = require('path');
const app = express();

const port = process.env.PORT || 3000;

// Middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Routes
const apiRoutes = require('./routes/api');
const viewRoutes = require('./routes/view');

app.use('/api/reports', apiRoutes);
app.use('/reports', viewRoutes);

// Health check
app.get('/ping', (req, res) => {
  res.json({ status: 'ok', message: 'Witty Report Visualization Service is running' });
});

// Start server
app.listen(port, () => {
  console.log(`Report Visualization Service listening at http://localhost:${port}`);
  console.log(`- API Endpoint: POST http://localhost:${port}/api/reports`);
});
