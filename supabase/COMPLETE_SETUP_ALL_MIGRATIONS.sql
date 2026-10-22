-- ================================================================
-- COMPLETE VOICE-PILOT SUPABASE SETUP SCRIPT
-- Run this single script in your Supabase SQL Editor
-- ================================================================


-- >>> START OF 001_initial_schema.sql <<<

-- 1. CORE TENANT TABLES

CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  avatar_url TEXT,
  subscription_tier TEXT DEFAULT 'free',
  billing_email TEXT,
  billing_address JSONB,
  stripe_customer_id TEXT UNIQUE,
  timezone TEXT DEFAULT 'UTC',
  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  owner_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  call_limit INT DEFAULT 1000,
  concurrent_call_limit INT DEFAULT 10,
  current_concurrent_calls INT DEFAULT 0,
  storage_limit_gb INT DEFAULT 100,
  storage_used_gb DECIMAL(10, 2) DEFAULT 0,
  timezone TEXT DEFAULT 'UTC',
  billing_email TEXT,
  webhook_url TEXT,
  slack_webhook TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE workspace_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(workspace_id, user_id)
);

CREATE TABLE agents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  avatar_url TEXT,
  status TEXT DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'training')),
  model TEXT NOT NULL DEFAULT 'gpt-4-turbo',
  system_prompt TEXT NOT NULL,
  temperature DECIMAL(3, 2) DEFAULT 0.7 CHECK (temperature BETWEEN 0 AND 2),
  max_tokens INT DEFAULT 150,
  voice_id TEXT NOT NULL DEFAULT 'en-US-Neural2-A',
  voice_provider TEXT DEFAULT 'elevenlabs' CHECK (voice_provider IN ('elevenlabs', 'azure', 'deepgram')),
  voice_speed DECIMAL(3, 2) DEFAULT 1.0,
  voice_pitch DECIMAL(4, 2) DEFAULT 1.0,
  interrupt_enabled BOOLEAN DEFAULT true,
  interrupt_threshold DECIMAL(3, 2) DEFAULT 0.8,
  language TEXT DEFAULT 'en-US',
  timezone TEXT,
  context_window_size INT DEFAULT 10,
  fallback_message TEXT,
  handoff_enabled BOOLEAN DEFAULT false,
  handoff_webhook_url TEXT,
  total_calls INT DEFAULT 0,
  avg_call_duration INT DEFAULT 0,
  success_rate DECIMAL(5, 2) DEFAULT 0,
  last_called_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES profiles(id)
);

CREATE TABLE phone_numbers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  agent_id UUID REFERENCES agents(id) ON DELETE SET NULL,
  phone_number TEXT NOT NULL,
  country_code TEXT NOT NULL,
  friendly_name TEXT,
  provider TEXT DEFAULT 'twilio',
  provider_id TEXT UNIQUE NOT NULL,
  inbound_enabled BOOLEAN DEFAULT true,
  outbound_enabled BOOLEAN DEFAULT true,
  sms_enabled BOOLEAN DEFAULT false,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
  purchased_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  inbound_calls INT DEFAULT 0,
  outbound_calls INT DEFAULT 0,
  last_call_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(workspace_id, phone_number)
);

CREATE TABLE calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  agent_id UUID NOT NULL REFERENCES agents(id),
  phone_number_id UUID NOT NULL REFERENCES phone_numbers(id),
  caller_phone_number TEXT NOT NULL,
  caller_name TEXT,
  twilio_call_sid TEXT UNIQUE NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  status TEXT DEFAULT 'created' CHECK (status IN (
    'created', 'ringing', 'in_progress', 'completed', 
    'failed', 'no_answer', 'canceled', 'busy'
  )),
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  ringing_duration INT DEFAULT 0,
  actual_duration INT DEFAULT 0,
  success BOOLEAN,
  drop_reason TEXT,
  sentiment_score DECIMAL(3, 2),
  user_satisfaction DECIMAL(5, 2),
  transfer_requested BOOLEAN DEFAULT false,
  cost_cents INT DEFAULT 0,
  recording_storage_mb DECIMAL(10, 2),
  metadata JSONB DEFAULT '{}',
  context JSONB DEFAULT '{}',
  recording_consent BOOLEAN NOT NULL DEFAULT false,
  recording_url TEXT,
  recording_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE call_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  audio_url TEXT,
  duration_ms INT,
  confidence DECIMAL(5, 4),
  sequence_number INT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  token_count INT,
  model_used TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(call_id, sequence_number)
);

CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  call_id UUID REFERENCES calls(id) ON DELETE SET NULL,
  type TEXT NOT NULL,
  severity TEXT DEFAULT 'info' CHECK (severity IN ('debug', 'info', 'warning', 'error', 'critical')),
  payload JSONB NOT NULL DEFAULT '{}',
  stack_trace TEXT,
  correlation_id TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE integrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  api_key_encrypted TEXT,
  api_secret_encrypted TEXT,
  config JSONB DEFAULT '{}',
  status TEXT DEFAULT 'active',
  webhook_url TEXT,
  webhook_secret TEXT,
  events_subscribed TEXT[] DEFAULT ARRAY[]::TEXT[],
  rate_limit INT,
  rate_limit_window INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  UNIQUE(workspace_id, type)
);

-- RLS POLICIES (Simplified for initial setup)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE phone_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;


-- >>> END OF 001_initial_schema.sql <<<


-- >>> START OF 002_chat_history.sql <<<

-- 1. Modify Calls Table to support Test Calls (nullable phone info)
ALTER TABLE calls ALTER COLUMN phone_number_id DROP NOT NULL;
ALTER TABLE calls ALTER COLUMN caller_phone_number DROP NOT NULL;

-- 2. Create Chat History Tables
CREATE TABLE chat_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  user_identifier TEXT, -- e.g. "Web User"
  status TEXT DEFAULT 'active',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Enable RLS
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- 4. Add Indexes
CREATE INDEX idx_chat_sessions_workspace ON chat_sessions(workspace_id);
CREATE INDEX idx_chat_sessions_agent ON chat_sessions(agent_id);
CREATE INDEX idx_chat_messages_session ON chat_messages(session_id);


-- >>> END OF 002_chat_history.sql <<<


-- >>> START OF 003_kb_columns.sql <<<

-- Add knowledge base and KB metadata columns to agents table
ALTER TABLE agents ADD COLUMN IF NOT EXISTS knowledge_base TEXT DEFAULT '';
ALTER TABLE agents ADD COLUMN IF NOT EXISTS kb_source_url TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS kb_metadata JSONB DEFAULT '{}';


-- >>> END OF 003_kb_columns.sql <<<


-- >>> START OF 004_scheduled_tasks.sql <<<

-- Create task_status enum
DO $$ BEGIN
    CREATE TYPE task_status AS ENUM (
        'scheduled',
        'running',
        'completed',
        'failed',
        'cancelled',
        'paused'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create scheduled_tasks table
CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    task_type VARCHAR(50) NOT NULL DEFAULT 'voice_call',
    title VARCHAR(255) NOT NULL,
    description TEXT,
    scheduled_time_utc TIMESTAMPTZ NOT NULL,
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    recurrence_rule TEXT, 
    status task_status NOT NULL DEFAULT 'scheduled',
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE scheduled_tasks ENABLE ROW LEVEL SECURITY;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_user_id ON scheduled_tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_workspace_id ON scheduled_tasks(workspace_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_status ON scheduled_tasks(status);
CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_next_run ON scheduled_tasks(next_run_at) WHERE status = 'scheduled';

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DO $$ BEGIN
    CREATE TRIGGER update_scheduled_tasks_updated_at
        BEFORE UPDATE ON scheduled_tasks
        FOR EACH ROW
        EXECUTE PROCEDURE update_updated_at_column();
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
-- RLS Policies
CREATE POLICY "Users can view their own scheduled tasks"
ON scheduled_tasks FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own scheduled tasks"
ON scheduled_tasks FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own scheduled tasks"
ON scheduled_tasks FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own scheduled tasks"
ON scheduled_tasks FOR DELETE
USING (auth.uid() = user_id);


-- >>> END OF 004_scheduled_tasks.sql <<<


-- >>> START OF 005_scheduled_task_logs.sql <<<

-- Create scheduled_task_logs table
CREATE TABLE IF NOT EXISTS scheduled_task_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheduled_task_id UUID NOT NULL REFERENCES scheduled_tasks(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL, -- e.g., 'success', 'failed', 'retrying'
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    duration_ms INT,
    attempt_number INT NOT NULL DEFAULT 1,
    result JSONB DEFAULT '{}'::jsonb,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE scheduled_task_logs ENABLE ROW LEVEL SECURITY;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_logs_task_id ON scheduled_task_logs(scheduled_task_id);
CREATE INDEX IF NOT EXISTS idx_task_logs_created_at ON scheduled_task_logs(created_at DESC);

-- Policy to ensure users can only see logs for tasks they own
-- Assuming users can see tasks in their workspaces
CREATE POLICY "Users can view logs for tasks in their workspaces"
ON scheduled_task_logs
FOR SELECT
USING (
    scheduled_task_id IN (
        SELECT id FROM scheduled_tasks WHERE workspace_id IN (
            SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
        )
    )
);


-- >>> END OF 005_scheduled_task_logs.sql <<<


-- >>> START OF 006_notifications.sql <<<

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) NOT NULL, -- e.g., 'task_created', 'task_completed', 'task_failed'
    metadata JSONB DEFAULT '{}'::jsonb,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read) WHERE is_read = FALSE;

-- Policy
CREATE POLICY "Users can view their own notifications"
ON notifications
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications"
ON notifications
FOR UPDATE
USING (auth.uid() = user_id);


-- >>> END OF 006_notifications.sql <<<


-- >>> START OF 008_workflows.sql <<<

-- Migration to add standalone workflows table
CREATE TABLE IF NOT EXISTS workflows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  nodes JSONB DEFAULT '[]',
  connections JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read/write their workspace workflows
CREATE POLICY "Allow authenticated access to workflows" 
ON workflows 
FOR ALL 
TO authenticated 
USING (true) 
WITH CHECK (true);


-- >>> END OF 008_workflows.sql <<<


-- >>> START OF 009_asterisk_support.sql <<<

-- Migration to support Asterisk & Multi-provider calls

-- 1. Alter calls table to make twilio_call_sid nullable (as Asterisk calls won't have it)
ALTER TABLE calls ALTER COLUMN twilio_call_sid DROP NOT NULL;

-- 2. Add columns for provider, call_uuid, caller_id, dialed_number, duration_seconds
ALTER TABLE calls ADD COLUMN IF NOT EXISTS call_uuid TEXT UNIQUE;
ALTER TABLE calls ADD COLUMN IF NOT EXISTS provider TEXT DEFAULT 'twilio';
ALTER TABLE calls ADD COLUMN IF NOT EXISTS caller_id TEXT;
ALTER TABLE calls ADD COLUMN IF NOT EXISTS dialed_number TEXT;
ALTER TABLE calls ADD COLUMN IF NOT EXISTS duration_seconds INT DEFAULT 0;


-- >>> END OF 009_asterisk_support.sql <<<


-- >>> START OF 010_sip_trunks.sql <<<

-- Migration to support SIP Trunk providers, DID numbers, and test results

-- 1. Create sip_trunk_providers table
CREATE TABLE IF NOT EXISTS sip_trunk_providers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  provider_type TEXT NOT NULL CHECK (provider_type IN ('airtel', 'jio', 'tata', 'twilio', 'exotel', 'myoperator', 'knowlarity', 'custom')),
  auth_type TEXT NOT NULL CHECK (auth_type IN ('ip_auth', 'username_password')),
  sip_proxy TEXT NOT NULL,
  sip_port INTEGER DEFAULT 5060,
  transport TEXT DEFAULT 'udp' CHECK (transport IN ('udp', 'tcp', 'tls')),
  username TEXT,
  password_encrypted TEXT,
  outbound_caller_id TEXT,
  provider_ips JSONB,
  allowed_codecs JSONB DEFAULT '["ulaw", "alaw"]'::jsonb,
  rtp_ip TEXT,
  max_concurrent_calls INTEGER DEFAULT 10,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'disabled', 'error')),
  last_checked_at TIMESTAMPTZ,
  last_error TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create did_numbers table
CREATE TABLE IF NOT EXISTS did_numbers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  sip_trunk_provider_id UUID REFERENCES sip_trunk_providers(id) ON DELETE SET NULL,
  phone_number TEXT NOT NULL,
  country_code TEXT NOT NULL,
  label TEXT,
  provider TEXT,
  agent_id UUID REFERENCES agents(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'pending')),
  inbound_enabled BOOLEAN DEFAULT true,
  outbound_enabled BOOLEAN DEFAULT false,
  recording_enabled BOOLEAN DEFAULT false,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(workspace_id, phone_number)
);

-- 3. Create sip_trunk_test_results table
CREATE TABLE IF NOT EXISTS sip_trunk_test_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  sip_trunk_provider_id UUID NOT NULL REFERENCES sip_trunk_providers(id) ON DELETE CASCADE,
  test_type TEXT NOT NULL CHECK (test_type IN ('config_validation', 'dns_check', 'firewall_check', 'asterisk_reload', 'inbound_call', 'outbound_call')),
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'pending')),
  result JSONB DEFAULT '{}'::jsonb,
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Alter calls table to make phone_number_id nullable and add did_number_id
ALTER TABLE calls ALTER COLUMN phone_number_id DROP NOT NULL;
ALTER TABLE calls ADD COLUMN IF NOT EXISTS did_number_id UUID REFERENCES did_numbers(id) ON DELETE SET NULL;

-- Enable Row Level Security
ALTER TABLE sip_trunk_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE did_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE sip_trunk_test_results ENABLE ROW LEVEL SECURITY;


-- >>> END OF 010_sip_trunks.sql <<<


-- >>> START OF 011_sso_nonces.sql <<<

-- Migration: Add sso_nonces table for SSO login replay prevention
CREATE TABLE IF NOT EXISTS public.sso_nonces (
    jti UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.sso_nonces ENABLE ROW LEVEL SECURITY;

-- Allow service_role full access (used by the python backend with service role client)
CREATE POLICY "Allow service role full access" ON public.sso_nonces
    FOR ALL TO service_role USING (true) WITH CHECK (true);


-- >>> END OF 011_sso_nonces.sql <<<


-- >>> START OF 012_admin_panel.sql <<<

-- Migration to support Production Admin Panel

-- 1. Add role to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user';

-- 2. Create admin_audit_logs table
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT,
  details JSONB DEFAULT '{}'::jsonb,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Create workspace_limits table
CREATE TABLE IF NOT EXISTS public.workspace_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE UNIQUE,
  monthly_minute_limit INTEGER DEFAULT 1000,
  max_concurrent_calls INTEGER DEFAULT 5,
  inbound_enabled BOOLEAN DEFAULT true,
  outbound_enabled BOOLEAN DEFAULT true,
  billing_status TEXT DEFAULT 'active' CHECK (billing_status IN ('trial', 'active', 'overdue', 'suspended')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Create billing_usage_snapshots table
CREATE TABLE IF NOT EXISTS public.billing_usage_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  year_month TEXT NOT NULL,
  stt_minutes NUMERIC DEFAULT 0.0,
  stt_cost NUMERIC DEFAULT 0.0,
  tts_characters INTEGER DEFAULT 0,
  tts_cost NUMERIC DEFAULT 0.0,
  llm_tokens_input INTEGER DEFAULT 0,
  llm_tokens_output INTEGER DEFAULT 0,
  llm_cost NUMERIC DEFAULT 0.0,
  sip_minutes NUMERIC DEFAULT 0.0,
  sip_cost NUMERIC DEFAULT 0.0,
  total_cost NUMERIC DEFAULT 0.0,
  plan_price NUMERIC DEFAULT 0.0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(workspace_id, year_month)
);

-- 5. Create system_health_checks table
CREATE TABLE IF NOT EXISTS public.system_health_checks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  checked_at TIMESTAMPTZ DEFAULT now(),
  status TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb
);

-- 6. Create encrypted_settings table
CREATE TABLE IF NOT EXISTS public.encrypted_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_name TEXT UNIQUE NOT NULL,
  encrypted_value TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_usage_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_health_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encrypted_settings ENABLE ROW LEVEL SECURITY;


-- >>> END OF 012_admin_panel.sql <<<


-- >>> START OF 013_profiles_policy.sql <<<

-- Migration to allow users to read their own profiles

CREATE POLICY "Allow users to read their own profile"
ON public.profiles
FOR SELECT
TO authenticated
USING (auth.uid() = id);


-- >>> END OF 013_profiles_policy.sql <<<


-- >>> START OF 014_calls_policies.sql <<<

-- Migration to allow authenticated users to read and write calls and call_messages

CREATE POLICY "Allow authenticated users to manage calls"
ON public.calls
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

CREATE POLICY "Allow authenticated users to manage call_messages"
ON public.call_messages
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);


-- >>> END OF 014_calls_policies.sql <<<


-- >>> START OF 015_016_combined_safe.sql <<<

-- ================================================================
-- COMBINED MIGRATION: 015 + 016
-- Run this entire script in Supabase SQL Editor.
-- All statements use IF NOT EXISTS / IF EXISTS for safety.
-- ================================================================

-- ================================================================
-- MIGRATION 015: Call Admission Control
-- ================================================================

-- 1. Create call_limit_events table
CREATE TABLE IF NOT EXISTS public.call_limit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID,
  agent_id UUID,
  sip_trunk_provider_id UUID,
  did_number_id UUID,
  call_uuid TEXT,
  direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  reason TEXT NOT NULL,
  caller_id TEXT,
  dialed_number TEXT,
  destination_number TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create workspace_usage_counters table
CREATE TABLE IF NOT EXISTS public.workspace_usage_counters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  billing_month TEXT NOT NULL,
  used_seconds INTEGER DEFAULT 0,
  used_minutes NUMERIC DEFAULT 0,
  estimated_cost NUMERIC DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(workspace_id, billing_month)
);

-- 3. Add workspace_limits columns safely
ALTER TABLE public.workspace_limits ADD COLUMN IF NOT EXISTS monthly_minute_limit INTEGER DEFAULT 1000;
ALTER TABLE public.workspace_limits ADD COLUMN IF NOT EXISTS max_concurrent_calls INTEGER DEFAULT 1;
ALTER TABLE public.workspace_limits ADD COLUMN IF NOT EXISTS inbound_enabled BOOLEAN DEFAULT true;
ALTER TABLE public.workspace_limits ADD COLUMN IF NOT EXISTS outbound_enabled BOOLEAN DEFAULT true;

-- Add billing_status only if it doesn't exist (check constraint added separately below)
ALTER TABLE public.workspace_limits ADD COLUMN IF NOT EXISTS billing_status TEXT DEFAULT 'active';

-- Safely add or replace the check constraint on billing_status
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workspace_limits_billing_status_check'
  ) THEN
    ALTER TABLE public.workspace_limits
      ADD CONSTRAINT workspace_limits_billing_status_check
      CHECK (billing_status IN ('trial', 'active', 'overdue', 'suspended'));
  END IF;
END$$;

-- 4. Add max_concurrent_calls to sip_trunk_providers
ALTER TABLE public.sip_trunk_providers ADD COLUMN IF NOT EXISTS max_concurrent_calls INTEGER DEFAULT 10;

-- 5. Add max_concurrent_calls to agents
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS max_concurrent_calls INTEGER DEFAULT NULL;

-- 6. Add columns to calls table
ALTER TABLE public.calls ADD COLUMN IF NOT EXISTS sip_trunk_provider_id UUID REFERENCES public.sip_trunk_providers(id) ON DELETE SET NULL;
ALTER TABLE public.calls ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE public.calls ADD COLUMN IF NOT EXISTS hangup_reason TEXT;
ALTER TABLE public.calls ADD COLUMN IF NOT EXISTS estimated_cost NUMERIC DEFAULT 0;

-- Enable RLS on new tables
ALTER TABLE public.call_limit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_usage_counters ENABLE ROW LEVEL SECURITY;


-- ================================================================
-- MIGRATION 016: Admin Production Safety
-- ================================================================

-- 1. Create admin_audit_logs if missing
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id uuid,
    action text NOT NULL,
    target_type text,
    target_id text,
    old_value jsonb DEFAULT '{}',
    new_value jsonb DEFAULT '{}',
    metadata jsonb DEFAULT '{}',
    ip_address text,
    user_agent text,
    created_at timestamptz DEFAULT now()
);

-- Ensure all columns exist in case table was created previously with fewer columns
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS admin_user_id uuid;
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS action text;
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS target_type text;
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS target_id text;
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS old_value jsonb DEFAULT '{}';
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS new_value jsonb DEFAULT '{}';
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}';
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS ip_address text;
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS user_agent text;
ALTER TABLE public.admin_audit_logs ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_user_date ON public.admin_audit_logs (admin_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_action_date ON public.admin_audit_logs (action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_target ON public.admin_audit_logs (target_type, target_id);

-- 2. Create asterisk_config_versions if missing
CREATE TABLE IF NOT EXISTS public.asterisk_config_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number integer NOT NULL,
    config_type text NOT NULL,
    pjsip_config text,
    extensions_config text,
    metadata jsonb DEFAULT '{}',
    generated_by uuid,
    validation_status text DEFAULT 'pending',
    validation_error text,
    reload_status text DEFAULT 'not_reloaded',
    reload_error text,
    registration_status text DEFAULT 'healthy' CHECK (registration_status IN ('healthy', 'warning', 'failed')),
    registration_warning text,
    rollback_available boolean DEFAULT true,
    is_active boolean DEFAULT false,
    rollback_of uuid,
    created_at timestamptz DEFAULT now(),
    applied_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_asterisk_config_versions_num ON public.asterisk_config_versions (version_number);
CREATE INDEX IF NOT EXISTS idx_asterisk_config_versions_active ON public.asterisk_config_versions (is_active);
CREATE INDEX IF NOT EXISTS idx_asterisk_config_versions_date ON public.asterisk_config_versions (created_at DESC);

-- 3. Create provider_health_events if missing
CREATE TABLE IF NOT EXISTS public.provider_health_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider text NOT NULL,
    service_type text NOT NULL,
    status text NOT NULL CHECK (status IN ('success', 'failure', '429_rate_limited')),
    latency_ms integer,
    error_code text,
    error_message text,
    workspace_id uuid,
    agent_id uuid,
    call_uuid text,
    metadata jsonb DEFAULT '{}',
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_provider_health_prov ON public.provider_health_events (provider, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_provider_health_srv ON public.provider_health_events (service_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_provider_health_stat ON public.provider_health_events (status, created_at DESC);

-- 4. Create batch_call_runs if missing
CREATE TABLE IF NOT EXISTS public.batch_call_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id uuid NOT NULL,
    agent_id uuid,
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'paused', 'stopped', 'completed')),
    total_numbers integer DEFAULT 0,
    queued_count integer DEFAULT 0,
    dialed_count integer DEFAULT 0,
    connected_count integer DEFAULT 0,
    failed_count integer DEFAULT 0,
    rejected_count integer DEFAULT 0,
    cac_rejected_count integer DEFAULT 0,
    estimated_cost numeric DEFAULT 0,
    started_at timestamptz,
    ended_at timestamptz,
    created_at timestamptz DEFAULT now(),
    metadata jsonb DEFAULT '{}'
);

-- 5. Create batch_call_items if missing
CREATE TABLE IF NOT EXISTS public.batch_call_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_run_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    agent_id uuid,
    phone_number text NOT NULL,
    call_uuid text,
    status text DEFAULT 'queued' CHECK (status IN ('queued', 'dialing', 'connected', 'failed', 'rejected', 'cac_rejected')),
    rejection_reason text,
    failure_reason text,
    started_at timestamptz,
    ended_at timestamptz,
    created_at timestamptz DEFAULT now(),
    metadata jsonb DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_batch_call_items_run ON public.batch_call_items (batch_run_id);
CREATE INDEX IF NOT EXISTS idx_batch_call_items_workspace ON public.batch_call_items (workspace_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_batch_call_items_status ON public.batch_call_items (status);

-- 6. Add tracking columns to existing tables
ALTER TABLE public.sip_trunk_providers
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS updated_by uuid;

ALTER TABLE public.did_numbers
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS updated_by uuid;

ALTER TABLE public.workspace_limits
  ADD COLUMN IF NOT EXISTS updated_by uuid;

-- ================================================================
-- FIX: Update agents.voice_provider check constraint
-- Add sarvam and cartesia to allowed providers
-- ================================================================
DO $$
BEGIN
  -- Drop old constraint if it exists (ignores error if not present)
  ALTER TABLE public.agents DROP CONSTRAINT IF EXISTS agents_voice_provider_check;
EXCEPTION WHEN OTHERS THEN
  NULL;
END$$;

ALTER TABLE public.agents
  ADD CONSTRAINT agents_voice_provider_check
  CHECK (voice_provider IN ('elevenlabs', 'openai', 'deepgram', 'google', 'azure', 'aws', 'sarvam', 'cartesia'));


-- >>> END OF 015_016_combined_safe.sql <<<


-- >>> START OF 017_batch_call_production_fix.sql <<<

-- ================================================================
-- MIGRATION 017: Batch Call System Production Fixes
-- ================================================================

-- 1. Safely drop inline status check constraints if they exist
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Drop status constraints for batch_call_runs
    FOR r IN (
        SELECT conname 
        FROM pg_constraint 
        WHERE conrelid = 'public.batch_call_runs'::regclass AND conname LIKE '%status%'
    ) LOOP
        EXECUTE 'ALTER TABLE public.batch_call_runs DROP CONSTRAINT ' || quote_ident(r.conname);
    END LOOP;

    -- Drop status constraints for batch_call_items
    FOR r IN (
        SELECT conname 
        FROM pg_constraint 
        WHERE conrelid = 'public.batch_call_items'::regclass AND conname LIKE '%status%'
    ) LOOP
        EXECUTE 'ALTER TABLE public.batch_call_items DROP CONSTRAINT ' || quote_ident(r.conname);
    END LOOP;
END $$;

-- 2. Re-add status check constraints with extended statuses
ALTER TABLE public.batch_call_runs
  ADD CONSTRAINT batch_call_runs_status_check
  CHECK (status IN ('draft', 'pending', 'queued', 'running', 'paused', 'stopped', 'completed', 'cancelled', 'failed'));

ALTER TABLE public.batch_call_items
  ADD CONSTRAINT batch_call_items_status_check
  CHECK (status IN ('queued', 'dialing', 'connected', 'completed', 'no_answer', 'busy', 'failed', 'retry_later', 'cac_rejected', 'invalid_number', 'cancelled', 'rejected'));

-- 3. Add retry policy and locking columns to batch_call_items
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS attempt_count INTEGER DEFAULT 0;
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS max_attempts INTEGER DEFAULT 2;
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS last_error TEXT DEFAULT NULL;
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS last_cac_reason TEXT DEFAULT NULL;
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE public.batch_call_items ADD COLUMN IF NOT EXISTS reservation_id TEXT DEFAULT NULL;

-- 4. Add configuration and new counters to batch_call_runs
ALTER TABLE public.batch_call_runs ADD COLUMN IF NOT EXISTS max_parallel_calls INTEGER DEFAULT 1;
ALTER TABLE public.batch_call_runs ADD COLUMN IF NOT EXISTS attempted_count INTEGER DEFAULT 0;
ALTER TABLE public.batch_call_runs ADD COLUMN IF NOT EXISTS completed_count INTEGER DEFAULT 0;
ALTER TABLE public.batch_call_runs ADD COLUMN IF NOT EXISTS retry_count INTEGER DEFAULT 0;
ALTER TABLE public.batch_call_runs ADD COLUMN IF NOT EXISTS cancelled_count INTEGER DEFAULT 0;

-- 5. Create call_reservations table for persistent audit & stale recovery
CREATE TABLE IF NOT EXISTS public.call_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_uuid TEXT NOT NULL UNIQUE,
    direction TEXT NOT NULL,
    workspace_id UUID NOT NULL,
    agent_id UUID NOT NULL,
    sip_trunk_provider_id UUID,
    did_number_id UUID,
    status TEXT DEFAULT 'reserved' CHECK (status IN ('reserved', 'released')),
    expires_at TIMESTAMPTZ NOT NULL,
    released_at TIMESTAMPTZ DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_call_reservations_uuid ON public.call_reservations(call_uuid);
CREATE INDEX IF NOT EXISTS idx_call_reservations_status ON public.call_reservations(status);


-- >>> END OF 017_batch_call_production_fix.sql <<<


-- >>> START OF 018_batch_campaign_runtime_fixes.sql <<<

-- Migration 018: Batch campaign runtime fixes

-- 1. Check for orphaned workspace_id references in batch_call_runs
DO $$
DECLARE
    orphan_count integer;
BEGIN
    SELECT COUNT(*) INTO orphan_count
    FROM public.batch_call_runs
    WHERE workspace_id NOT IN (SELECT id FROM public.workspaces);
    
    IF orphan_count > 0 THEN
        RAISE EXCEPTION 'Migration aborted: Found % orphaned workspace_id references in batch_call_runs. Please perform manual database review.', orphan_count;
    END IF;

    -- Check for orphaned workspace_id references in batch_call_items
    SELECT COUNT(*) INTO orphan_count
    FROM public.batch_call_items
    WHERE workspace_id NOT IN (SELECT id FROM public.workspaces);
    
    IF orphan_count > 0 THEN
        RAISE EXCEPTION 'Migration aborted: Found % orphaned workspace_id references in batch_call_items. Please perform manual database review.', orphan_count;
    END IF;
END $$;

-- 2. Clean up orphaned agent_id references (set to NULL as agent_id is nullable)
UPDATE public.batch_call_runs 
SET agent_id = NULL 
WHERE agent_id IS NOT NULL 
  AND agent_id NOT IN (SELECT id FROM public.agents);

UPDATE public.batch_call_items 
SET agent_id = NULL 
WHERE agent_id IS NOT NULL 
  AND agent_id NOT IN (SELECT id FROM public.agents);

-- 3. Normalize legacy status values
-- Update runs from pending -> queued
UPDATE public.batch_call_runs 
SET status = 'queued' 
WHERE status = 'pending';

-- Update runs from stopped -> cancelled
UPDATE public.batch_call_runs 
SET status = 'cancelled' 
WHERE status = 'stopped';

-- Update items from stopped -> cancelled
UPDATE public.batch_call_items 
SET status = 'cancelled' 
WHERE status = 'stopped';

-- 4. Apply status check constraints to batch_call_runs
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT conname 
        FROM pg_constraint 
        WHERE conrelid = 'public.batch_call_runs'::regclass AND conname LIKE '%status%'
    ) LOOP
        EXECUTE 'ALTER TABLE public.batch_call_runs DROP CONSTRAINT ' || quote_ident(r.conname);
    END LOOP;
END $$;

ALTER TABLE public.batch_call_runs
ADD CONSTRAINT chk_batch_call_runs_status
CHECK (status IN ('draft', 'queued', 'running', 'paused', 'completed', 'cancelled', 'failed'));

-- 5. Add foreign key constraints with safe behaviors
ALTER TABLE public.batch_call_runs
DROP CONSTRAINT IF EXISTS fk_batch_call_runs_workspace,
DROP CONSTRAINT IF EXISTS fk_batch_call_runs_agent;

ALTER TABLE public.batch_call_runs
ADD CONSTRAINT fk_batch_call_runs_workspace
FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE public.batch_call_runs
ADD CONSTRAINT fk_batch_call_runs_agent
FOREIGN KEY (agent_id) REFERENCES public.agents(id) ON DELETE SET NULL;

ALTER TABLE public.batch_call_items
DROP CONSTRAINT IF EXISTS fk_batch_call_items_run,
DROP CONSTRAINT IF EXISTS fk_batch_call_items_workspace,
DROP CONSTRAINT IF EXISTS fk_batch_call_items_agent;

ALTER TABLE public.batch_call_items
ADD CONSTRAINT fk_batch_call_items_run
FOREIGN KEY (batch_run_id) REFERENCES public.batch_call_runs(id) ON DELETE CASCADE;

ALTER TABLE public.batch_call_items
ADD CONSTRAINT fk_batch_call_items_workspace
FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE public.batch_call_items
ADD CONSTRAINT fk_batch_call_items_agent
FOREIGN KEY (agent_id) REFERENCES public.agents(id) ON DELETE SET NULL;

-- 6. Reload schema for PostgREST
NOTIFY pgrst, 'reload schema';


-- >>> END OF 018_batch_campaign_runtime_fixes.sql <<<


-- >>> START OF 019_outbound_dial_safety_kill_switches.sql <<<

-- Migration 019: Outbound dial safety and kill switches tracking

-- 1. Add dry_run column to batch_call_runs
ALTER TABLE public.batch_call_runs 
ADD COLUMN IF NOT EXISTS dry_run BOOLEAN DEFAULT false;

-- 2. Add safety tracking columns to batch_call_items
ALTER TABLE public.batch_call_items 
ADD COLUMN IF NOT EXISTS safety_result JSONB,
ADD COLUMN IF NOT EXISTS safety_reason_code TEXT,
ADD COLUMN IF NOT EXISTS safety_blocked_at TIMESTAMPTZ;

-- 3. Create outbound_safety_events table for auditing blocked dials
CREATE TABLE IF NOT EXISTS public.outbound_safety_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID,
    batch_run_id UUID,
    batch_item_id UUID,
    agent_id UUID,
    call_uuid TEXT,
    event_type TEXT,
    masked_phone_number TEXT,
    reason_code TEXT,
    safe_to_retry BOOLEAN,
    should_pause_campaign BOOLEAN,
    worker_instance_id TEXT,
    dry_run BOOLEAN,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';


-- >>> END OF 019_outbound_dial_safety_kill_switches.sql <<<


-- ================================================================
-- ADDITIONAL REQUIRED APPLICATION TABLES
-- ================================================================

-- 1. agent_contexts
CREATE TABLE IF NOT EXISTS public.agent_contexts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id UUID NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE UNIQUE,
  knowledge_base TEXT DEFAULT '',
  agent_system_prompt TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. call_usage
CREATE TABLE IF NOT EXISTS public.call_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id TEXT NOT NULL UNIQUE,
  workspace_id UUID REFERENCES public.workspaces(id) ON DELETE SET NULL,
  agent_id UUID REFERENCES public.agents(id) ON DELETE SET NULL,
  duration_seconds INTEGER DEFAULT 0,
  stt_minutes NUMERIC DEFAULT 0.0,
  stt_cost_inr NUMERIC DEFAULT 0.0,
  tts_characters INTEGER DEFAULT 0,
  tts_cost_inr NUMERIC DEFAULT 0.0,
  llm_input_tokens INTEGER DEFAULT 0,
  llm_output_tokens INTEGER DEFAULT 0,
  llm_cost_inr NUMERIC DEFAULT 0.0,
  telephony_cost_inr NUMERIC DEFAULT 0.0,
  total_cost_inr NUMERIC DEFAULT 0.0,
  cost_status TEXT DEFAULT 'pending',
  cost_finalized_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. hub_subscriptions
CREATE TABLE IF NOT EXISTS public.hub_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  plan TEXT DEFAULT 'Free',
  plan_id TEXT,
  subscription_status TEXT DEFAULT 'active',
  expires_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. niche_system_prompts
CREATE TABLE IF NOT EXISTS public.niche_system_prompts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL UNIQUE,
  system_prompt TEXT NOT NULL,
  category TEXT,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. wallet_transactions
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  amount NUMERIC NOT NULL,
  type TEXT DEFAULT 'call_usage',
  call_id TEXT,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Insert sample default niche system prompts if table is empty
INSERT INTO public.niche_system_prompts (niche_name, system_prompt, category)
VALUES
('Real Estate Lead Qualifier', 'You are an AI assistant for a premier real estate brokerage. Your goal is to qualify inbound leads by asking about their preferred location, budget, property type, and timeline.', 'Real Estate'),
('Healthcare Appointment Scheduler', 'You are a compassionate medical receptionist AI. You assist patients with scheduling, rescheduling, or canceling appointments, and confirming their insurance details.', 'Healthcare'),
('Customer Support Specialist', 'You are a helpful, professional customer support agent. You listen carefully to user issues, provide clear step-by-step guidance, and escalate complex problems to human agents.', 'Support'),
('E-commerce Sales Assistant', 'You are an engaging AI sales specialist for an online store. You assist shoppers with product recommendations, order status updates, and return policies.', 'E-commerce'),
('Dental Clinic Receptionist', 'You are a warm, welcoming dental clinic AI assistant. You help patients book dental cleanings, check-ups, and urgent dental consultations.', 'Dental')
ON CONFLICT (niche_name) DO NOTHING;

-- RLS policies for additional tables
ALTER TABLE public.hub_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.niche_system_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to niche_system_prompts"
ON public.niche_system_prompts FOR SELECT TO public USING (true);

CREATE POLICY "Allow authenticated read/write access to hub_subscriptions"
ON public.hub_subscriptions FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Allow service role full access to wallet_transactions"
ON public.wallet_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);


-- >>> START OF 020_enable_rls_all_tables.sql <<<

-- Migration 020: Enable Row Level Security (RLS) and define access policies for flagged public tables

-- 1. Enable RLS on all flagged tables
ALTER TABLE public.outbound_safety_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sso_nonces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asterisk_config_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.batch_call_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_health_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_contexts ENABLE ROW LEVEL SECURITY;

-- 2. Define Policies for Backend-Only Tables (service_role full access)
-- Note: Supabase service_role key bypasses RLS by default, but defining these explicitly guarantees safe access.

-- outbound_safety_events
DROP POLICY IF EXISTS "Allow service role full access" ON public.outbound_safety_events;
CREATE POLICY "Allow service role full access" ON public.outbound_safety_events
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- call_usage
DROP POLICY IF EXISTS "Allow service role full access" ON public.call_usage;
CREATE POLICY "Allow service role full access" ON public.call_usage
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- sso_nonces
DROP POLICY IF EXISTS "Allow service role full access" ON public.sso_nonces;
CREATE POLICY "Allow service role full access" ON public.sso_nonces
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- asterisk_config_versions
DROP POLICY IF EXISTS "Allow service role full access" ON public.asterisk_config_versions;
CREATE POLICY "Allow service role full access" ON public.asterisk_config_versions
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- batch_call_items
DROP POLICY IF EXISTS "Allow service role full access" ON public.batch_call_items;
CREATE POLICY "Allow service role full access" ON public.batch_call_items
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- provider_health_events
DROP POLICY IF EXISTS "Allow service role full access" ON public.provider_health_events;
CREATE POLICY "Allow service role full access" ON public.provider_health_events
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- call_reservations
DROP POLICY IF EXISTS "Allow service role full access" ON public.call_reservations;
CREATE POLICY "Allow service role full access" ON public.call_reservations
    FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 3. Define Policies for Frontend/Backend Accessed Table (agent_contexts)
-- Allow authenticated users (frontend client) full read/write management access to agent_contexts
DROP POLICY IF EXISTS "Allow authenticated users to manage agent_contexts" ON public.agent_contexts;
CREATE POLICY "Allow authenticated users to manage agent_contexts" ON public.agent_contexts
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow service role full access" ON public.agent_contexts;
CREATE POLICY "Allow service role full access" ON public.agent_contexts
    FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';


-- >>> END OF 020_enable_rls_all_tables.sql <<<
