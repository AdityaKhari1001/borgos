-- BorgOS Database Schema
-- Version 2.0 - MVP with Project Monitoring

-- Create database if not exists
-- CREATE DATABASE IF NOT EXISTS borgos;

-- Projects table (Zenith Coder integration)
CREATE TABLE IF NOT EXISTS projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    path VARCHAR(500) UNIQUE NOT NULL,
    zenith_id VARCHAR(100),
    project_type VARCHAR(100),
    tech_stack JSONB DEFAULT '[]'::jsonb,
    health_score INTEGER DEFAULT 0,
    vibe_score INTEGER DEFAULT 75,
    eco_score INTEGER DEFAULT 80,
    errors JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_scan TIMESTAMP
);

-- Deployments tracking table
CREATE TABLE IF NOT EXISTS deployments (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    port INTEGER UNIQUE NOT NULL CHECK (port >= 1024 AND port <= 65535),
    status VARCHAR(50) DEFAULT 'stopped',
    container_id VARCHAR(100),
    container_name VARCHAR(255),
    image_name VARCHAR(255),
    url VARCHAR(500),
    health_check_url VARCHAR(500),
    environment JSONB DEFAULT '{}'::jsonb,
    volumes JSONB DEFAULT '[]'::jsonb,
    networks JSONB DEFAULT '[]'::jsonb,
    cpu_limit VARCHAR(10),
    memory_limit VARCHAR(10),
    started_at TIMESTAMP,
    stopped_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Error logs table
CREATE TABLE IF NOT EXISTS error_logs (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    deployment_id INTEGER REFERENCES deployments(id) ON DELETE CASCADE,
    error_type VARCHAR(100),
    severity VARCHAR(20) DEFAULT 'error', -- debug, info, warning, error, critical
    message TEXT,
    stack_trace TEXT,
    context JSONB DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP,
    resolution TEXT
);

-- Agent tasks table (for Agent Zero integration)
CREATE TABLE IF NOT EXISTS agent_tasks (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    agent_type VARCHAR(50), -- 'agent-zero', 'zenith', 'gen-agent'
    task_type VARCHAR(100),
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending', -- pending, running, completed, failed
    priority INTEGER DEFAULT 1,
    input_data JSONB DEFAULT '{}'::jsonb,
    output_data JSONB DEFAULT '{}'::jsonb,
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- MCP queries table (Model Context Protocol)
CREATE TABLE IF NOT EXISTS mcp_queries (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    query_type VARCHAR(100),
    query TEXT,
    context JSONB DEFAULT '{}'::jsonb,
    response JSONB DEFAULT '{}'::jsonb,
    model_used VARCHAR(100),
    tokens_used INTEGER,
    response_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- System metrics table
CREATE TABLE IF NOT EXISTS system_metrics (
    id SERIAL PRIMARY KEY,
    metric_type VARCHAR(50), -- cpu, memory, disk, network
    value FLOAT,
    unit VARCHAR(20),
    metadata JSONB DEFAULT '{}'::jsonb,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Project dependencies table
CREATE TABLE IF NOT EXISTS project_dependencies (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    dependency_name VARCHAR(255),
    version VARCHAR(50),
    type VARCHAR(50), -- npm, pip, docker, system
    is_outdated BOOLEAN DEFAULT false,
    latest_version VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Deployment history table
CREATE TABLE IF NOT EXISTS deployment_history (
    id SERIAL PRIMARY KEY,
    deployment_id INTEGER REFERENCES deployments(id) ON DELETE CASCADE,
    action VARCHAR(50), -- start, stop, restart, update, scale
    old_status VARCHAR(50),
    new_status VARCHAR(50),
    performed_by VARCHAR(100),
    reason TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Vector embeddings table (for ChromaDB integration)
CREATE TABLE IF NOT EXISTS vector_embeddings (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    document_id VARCHAR(255) UNIQUE,
    content TEXT,
    embedding_model VARCHAR(100),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Agent Zero specific tables
CREATE TABLE IF NOT EXISTS agent_logs (
    id SERIAL PRIMARY KEY,
    agent_type VARCHAR(50) NOT NULL,
    status VARCHAR(50),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS agent_zero_sessions (
    id SERIAL PRIMARY KEY,
    session_id UUID DEFAULT gen_random_uuid(),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    total_messages INTEGER DEFAULT 0,
    total_tasks INTEGER DEFAULT 0,
    memory_data JSONB,
    config JSONB
);

CREATE TABLE IF NOT EXISTS agent_subordinates (
    id SERIAL PRIMARY KEY,
    parent_agent VARCHAR(100),
    subordinate_name VARCHAR(100) NOT NULL,
    subordinate_role VARCHAR(100),
    capabilities TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    metadata JSONB
);

-- Create indexes for better performance
CREATE INDEX idx_projects_active ON projects(is_active);
CREATE INDEX idx_projects_zenith_id ON projects(zenith_id);
CREATE INDEX idx_deployments_status ON deployments(status);
CREATE INDEX idx_deployments_port ON deployments(port);
CREATE INDEX idx_error_logs_severity ON error_logs(severity);
CREATE INDEX idx_error_logs_occurred ON error_logs(occurred_at);
CREATE INDEX idx_agent_tasks_status ON agent_tasks(status);
CREATE INDEX idx_mcp_queries_created ON mcp_queries(created_at);
CREATE INDEX idx_agent_logs_type ON agent_logs(agent_type);
CREATE INDEX idx_agent_logs_timestamp ON agent_logs(timestamp);
CREATE INDEX idx_agent_zero_sessions_active ON agent_zero_sessions(ended_at) WHERE ended_at IS NULL;
CREATE INDEX idx_agent_subordinates_parent ON agent_subordinates(parent_agent);

-- Create update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to tables with updated_at
CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_deployments_updated_at BEFORE UPDATE ON deployments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert default data
INSERT INTO projects (name, path, project_type, tech_stack) VALUES 
    ('BorgOS Core', '/opt/borgos', 'system', '["python", "fastapi", "postgresql", "redis"]'::jsonb),
    ('Zenith Coder', '/opt/borgos/agents/zenith', 'ai-agent', '["python", "react", "typescript"]'::jsonb),
    ('Agent Zero', '/opt/borgos/agents/zero', 'ai-agent', '["python", "mcp", "docker", "browser"]'::jsonb)
ON CONFLICT DO NOTHING;

-- Create view for active deployments with project info
CREATE OR REPLACE VIEW active_deployments AS
SELECT 
    d.*,
    p.name as project_name,
    p.tech_stack,
    p.health_score
FROM deployments d
JOIN projects p ON d.project_id = p.id
WHERE d.status IN ('running', 'healthy');

-- Create view for recent errors
CREATE OR REPLACE VIEW recent_errors AS
SELECT 
    e.*,
    p.name as project_name,
    d.name as deployment_name
FROM error_logs e
LEFT JOIN projects p ON e.project_id = p.id
LEFT JOIN deployments d ON e.deployment_id = d.id
WHERE e.occurred_at > CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY e.occurred_at DESC;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO borgos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO borgos;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO borgos;