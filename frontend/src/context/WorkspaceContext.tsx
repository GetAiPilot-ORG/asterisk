import React, { createContext, useCallback, useContext, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from './AuthContext'

import { getApiUrl } from '@/lib/api'

interface WorkspaceContextType {
  workspaceId: string | null
  authHeaders: Record<string, string> | null
  loading: boolean
  error: string | null
  refetch: () => Promise<void>
}

const WorkspaceContext = createContext<WorkspaceContextType>({
  workspaceId: null,
  authHeaders: null,
  loading: true,
  error: null,
  refetch: async () => {},
})

export const useWorkspace = () => useContext(WorkspaceContext)

const apiUrl = getApiUrl()

export function WorkspaceProvider({ children }: { children: React.ReactNode }) {
  const { session } = useAuth()
  const [workspaceId, setWorkspaceId] = useState<string | null>(null)
  const [authHeaders, setAuthHeaders] = useState<Record<string, string> | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const setupWorkspace = useCallback(async () => {
    if (!session) {
      setWorkspaceId(null)
      setAuthHeaders(null)
      setLoading(false)
      return
    }

    try {
      setLoading(true)
      setError(null)

      const headers = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${session.access_token}`,
        'ngrok-skip-browser-warning': 'true',
      }
      setAuthHeaders(headers)

      const setupRes = await fetch(`${apiUrl}/api/v1/workspaces/setup`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          user_id: session.user.id,
          email: session.user.email,
        }),
      })

      if (!setupRes.ok) throw new Error(`Workspace setup failed: ${setupRes.status}`)
      const { workspace_id } = await setupRes.json()
      setWorkspaceId(workspace_id)
    } catch (err) {
      console.error('[WorkspaceContext] setup error:', err)
      setError(err instanceof Error ? err.message : 'Workspace setup failed')
    } finally {
      setLoading(false)
    }
  }, [session])

  useEffect(() => {
    setupWorkspace()
  }, [setupWorkspace])

  return (
    <WorkspaceContext.Provider
      value={{ workspaceId, authHeaders, loading, error, refetch: setupWorkspace }}
    >
      {children}
    </WorkspaceContext.Provider>
  )
}
