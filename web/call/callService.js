(function (global) {
  function createCallService(supabaseClient, options) {
    const config = Object.assign({ defaultTimeoutMs: 30000 }, options || {});
    let incomingSubscription = null;

    async function startCall(calleeId, type) {
      const callerId = supabaseClient.auth?.user?.id || window.__currentUserId;
      if (!callerId) {
        throw new Error('No authenticated caller available.');
      }

      const { data, error } = await supabaseClient
        .from('calls')
        .insert({
          caller_id: callerId,
          callee_id: calleeId,
          type: type || 'audio',
          status: 'ringing',
          started_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (error) throw error;
      return data;
    }

    async function acceptCall(callId) {
      const now = new Date().toISOString();
      const { error } = await supabaseClient
        .from('calls')
        .update({ status: 'active', answered_at: now })
        .eq('id', callId);

      if (error) throw error;
      return true;
    }

    async function declineCall(callId) {
      const now = new Date().toISOString();
      const { error } = await supabaseClient
        .from('calls')
        .update({ status: 'declined', ended_at: now })
        .eq('id', callId);

      if (error) throw error;
      return true;
    }

    async function cancelCall(callId) {
      const now = new Date().toISOString();
      const { error } = await supabaseClient
        .from('calls')
        .update({ status: 'cancelled', ended_at: now })
        .eq('id', callId);

      if (error) throw error;
      return true;
    }

    async function endCall(callId) {
      const now = new Date().toISOString();
      const { error } = await supabaseClient
        .from('calls')
        .update({ status: 'ended', ended_at: now })
        .eq('id', callId);

      if (error) throw error;
      return true;
    }

    async function markMissed(callId) {
      const { error } = await supabaseClient
        .from('calls')
        .update({ status: 'missed', ended_at: new Date().toISOString() })
        .eq('id', callId)
        .eq('status', 'ringing');

      if (error) throw error;
      return true;
    }

    function listenForIncomingCalls(meId, onIncoming) {
      if (incomingSubscription) {
        supabaseClient.removeChannel(incomingSubscription);
      }

      incomingSubscription = supabaseClient.channel(`calls:${meId}`);
      incomingSubscription.on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'calls',
          filter: `callee_id=eq.${meId}`,
        },
        (payload) => {
          if (payload.new?.status === 'ringing') {
            onIncoming(payload.new);
          }
        }
      );

      incomingSubscription.subscribe();
      return incomingSubscription;
    }

    async function getCallHistory(meId) {
      const { data, error } = await supabaseClient
        .from('calls')
        .select('*')
        .or(`caller_id.eq.${meId},callee_id.eq.${meId}`)
        .order('started_at', { ascending: false });

      if (error) throw error;
      return data || [];
    }

    async function getCallById(callId) {
      const { data, error } = await supabaseClient.from('calls').select('*').eq('id', callId).single();
      if (error) throw error;
      return data;
    }

    function cleanup() {
      if (incomingSubscription) {
        supabaseClient.removeChannel(incomingSubscription);
        incomingSubscription = null;
      }
    }

    function scheduleMissed(callId) {
      setTimeout(() => {
        markMissed(callId).catch(() => undefined);
      }, config.defaultTimeoutMs);
    }

    return {
      startCall,
      acceptCall,
      declineCall,
      cancelCall,
      endCall,
      markMissed,
      listenForIncomingCalls,
      getCallHistory,
      getCallById,
      cleanup,
      scheduleMissed,
    };
  }

  global.createCallService = createCallService;
})(typeof window !== 'undefined' ? window : this);
