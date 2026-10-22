-- Migration: Add application tables required by frontend and backend
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

-- Pre-seed standard niche system prompts
INSERT INTO public.niche_system_prompts (niche_name, system_prompt, category)
VALUES
('Real Estate Lead Qualifier', 'You are an AI assistant for a premier real estate brokerage. Your goal is to qualify inbound leads by asking about their preferred location, budget, property type, and timeline.', 'Real Estate'),
('Healthcare Appointment Scheduler', 'You are a compassionate medical receptionist AI. You assist patients with scheduling, rescheduling, or canceling appointments, and confirming their insurance details.', 'Healthcare'),
('Customer Support Specialist', 'You are a helpful, professional customer support agent. You listen carefully to user issues, provide clear step-by-step guidance, and escalate complex problems to human agents.', 'Support'),
('E-commerce Sales Assistant', 'You are an engaging AI sales specialist for an online store. You assist shoppers with product recommendations, order status updates, and return policies.', 'E-commerce'),
('Dental Clinic Receptionist', 'You are a warm, welcoming dental clinic AI assistant. You help patients book dental cleanings, check-ups, and urgent dental consultations.', 'Dental')
ON CONFLICT (niche_name) DO NOTHING;

-- RLS policies
ALTER TABLE public.hub_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.niche_system_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read access to niche_system_prompts" ON public.niche_system_prompts;
CREATE POLICY "Allow public read access to niche_system_prompts"
ON public.niche_system_prompts FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Allow authenticated read/write access to hub_subscriptions" ON public.hub_subscriptions;
CREATE POLICY "Allow authenticated read/write access to hub_subscriptions"
ON public.hub_subscriptions FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow service role full access to wallet_transactions" ON public.wallet_transactions;
CREATE POLICY "Allow service role full access to wallet_transactions"
ON public.wallet_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);
