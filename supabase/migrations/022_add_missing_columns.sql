-- Migration 022: Add missing columns to agents and calls tables

-- 1. Agents table missing columns
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS agent_system_prompt TEXT DEFAULT '';
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS fallback_message TEXT;
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS handoff_enabled BOOLEAN DEFAULT false;
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS handoff_webhook_url TEXT;
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS niche TEXT;
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS is_custom_niche BOOLEAN DEFAULT false;

-- 2. Calls table missing columns
ALTER TABLE public.calls ADD COLUMN IF NOT EXISTS actual_duration INTEGER DEFAULT 0;

-- 3. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
