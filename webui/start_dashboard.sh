#!/bin/bash
# BorgOS Professional Dashboard Startup Script

echo "Starting BorgOS Professional Dashboard..."

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install requirements
echo "Installing dependencies..."
pip install -r requirements_dashboard.txt

# Create necessary directories
mkdir -p /etc/borgos
mkdir -p /var/lib/borgos
mkdir -p logs

# Set environment variables
export FLASK_APP=professional_dashboard.py
export FLASK_ENV=production

# Start the dashboard with gunicorn for production
echo "Starting dashboard on http://localhost:8080"
gunicorn --worker-class eventlet -w 1 --bind 0.0.0.0:8080 professional_dashboard:app --log-file logs/dashboard.log --access-logfile logs/access.log

# Alternative: For development/testing, use Flask's built-in server
# python professional_dashboard.py