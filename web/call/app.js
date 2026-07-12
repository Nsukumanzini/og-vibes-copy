(function (global) {
  function initCallDemo() {
    const state = {
      activeCall: null,
      incomingCall: null,
      callHistory: [],
      currentUserId: window.__currentUserId || 'user-a',
      peerUserId: 'user-b',
    };

    const els = {
      status: document.getElementById('status'),
      incomingCard: document.getElementById('incoming-card'),
      outgoingCard: document.getElementById('outgoing-card'),
      activeCard: document.getElementById('active-card'),
      historyList: document.getElementById('history-list'),
      startButton: document.getElementById('start-call'),
      acceptButton: document.getElementById('accept-call'),
      declineButton: document.getElementById('decline-call'),
      endButton: document.getElementById('end-call'),
      muteButton: document.getElementById('mute-call'),
      cameraButton: document.getElementById('camera-call'),
      message: document.getElementById('message'),
    };

    const supabaseClient = global.supabase;
    const callService = supabaseClient ? global.createCallService(supabaseClient) : null;

    function setStatus(message) {
      els.status.textContent = message;
    }

    function renderHistory() {
      if (!callService) {
        els.historyList.innerHTML = '<li>Supabase client not available.</li>';
        return;
      }

      callService.getCallHistory(state.currentUserId).then((history) => {
        state.callHistory = history;
        els.historyList.innerHTML = '';
        if (!history.length) {
          els.historyList.innerHTML = '<li>No calls yet.</li>';
          return;
        }

        history.slice(0, 8).forEach((item) => {
          const li = document.createElement('li');
          li.innerHTML = `<strong>${item.status}</strong> · ${item.type} · ${item.callee_id}`;
          els.historyList.appendChild(li);
        });
      }).catch(() => {
        els.historyList.innerHTML = '<li>Could not load history.</li>';
      });
    }

    function showIncoming(call) {
      state.incomingCall = call;
      els.incomingCard.hidden = false;
      els.outgoingCard.hidden = true;
      els.activeCard.hidden = true;
      els.message.textContent = `Incoming ${call.type} call from ${call.caller_id}`;
      setStatus('Incoming call');
    }

    function showOutgoing(call) {
      state.activeCall = call;
      els.outgoingCard.hidden = false;
      els.incomingCard.hidden = true;
      els.activeCard.hidden = true;
      setStatus(`Calling ${state.peerUserId}…`);
    }

    function showActive(call) {
      state.activeCall = call;
      els.activeCard.hidden = false;
      els.incomingCard.hidden = true;
      els.outgoingCard.hidden = true;
      setStatus('Call active');
    }

    async function startCall() {
      if (!callService) {
        setStatus('Add a Supabase client first.');
        return;
      }

      try {
        const call = await callService.startCall(state.peerUserId, 'video');
        showOutgoing(call);
        callService.scheduleMissed(call.id);
        setStatus('Call created');
      } catch (error) {
        setStatus(error.message || 'Failed to start call');
      }
    }

    async function acceptCall() {
      if (!state.incomingCall || !callService) return;
      await callService.acceptCall(state.incomingCall.id);
      showActive(state.incomingCall);
      renderHistory();
    }

    async function declineCall() {
      if (!state.incomingCall || !callService) return;
      await callService.declineCall(state.incomingCall.id);
      els.incomingCard.hidden = true;
      renderHistory();
    }

    async function endCall() {
      if (!state.activeCall || !callService) return;
      await callService.endCall(state.activeCall.id);
      els.activeCard.hidden = true;
      renderHistory();
    }

    els.startButton.addEventListener('click', startCall);
    els.acceptButton.addEventListener('click', acceptCall);
    els.declineButton.addEventListener('click', declineCall);
    els.endButton.addEventListener('click', endCall);

    if (callService) {
      callService.listenForIncomingCalls(state.currentUserId, (incomingCall) => {
        showIncoming(incomingCall);
      });
    }

    renderHistory();
  }

  document.addEventListener('DOMContentLoaded', initCallDemo);
})(typeof window !== 'undefined' ? window : this);
