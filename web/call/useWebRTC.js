(function (global) {
  function createWebRTCSession(options) {
    const config = Object.assign(
      {
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject' },
        ],
        onRemoteStream: null,
        onStateChange: null,
        onSignal: null,
        onError: null,
      },
      options || {}
    );

    let peerConnection = null;
    let localStream = null;
    let remoteStream = null;
    let channel = null;

    async function ensureMedia() {
      if (localStream) {
        return localStream;
      }

      try {
        localStream = await navigator.mediaDevices.getUserMedia({
          audio: true,
          video: config.video || true,
        });
        return localStream;
      } catch (error) {
        if (config.onError) {
          config.onError(error);
        }
        throw error;
      }
    }

    function initializePeerConnection() {
      if (peerConnection) {
        return peerConnection;
      }

      peerConnection = new RTCPeerConnection({ iceServers: config.iceServers });

      peerConnection.onicecandidate = (event) => {
        if (event.candidate && config.onSignal) {
          config.onSignal({ type: 'ice-candidate', candidate: event.candidate });
        }
      };

      peerConnection.ontrack = (event) => {
        remoteStream = event.streams[0];
        if (config.onRemoteStream) {
          config.onRemoteStream(remoteStream);
        }
      };

      peerConnection.oniceconnectionstatechange = () => {
        if (config.onStateChange) {
          config.onStateChange(peerConnection.iceConnectionState);
        }
      };

      return peerConnection;
    }

    async function attachLocalStream(stream) {
      const pc = initializePeerConnection();
      stream.getTracks().forEach((track) => {
        pc.addTrack(track, stream);
      });
      return stream;
    }

    async function createOffer() {
      const stream = await ensureMedia();
      await attachLocalStream(stream);
      const offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      return offer;
    }

    async function createAnswer(offer) {
      const stream = await ensureMedia();
      await attachLocalStream(stream);
      await peerConnection.setRemoteDescription(offer);
      const answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      return answer;
    }

    async function handleSignal(signal) {
      const pc = initializePeerConnection();
      if (signal.type === 'offer') {
        await pc.setRemoteDescription(signal);
      } else if (signal.type === 'answer') {
        await pc.setRemoteDescription(signal);
      } else if (signal.type === 'ice-candidate' && signal.candidate) {
        try {
          await pc.addIceCandidate(signal.candidate);
        } catch (error) {
          if (config.onError) {
            config.onError(error);
          }
        }
      } else if (signal.type === 'hangup') {
        await cleanup();
      }
    }

    async function joinChannel(callId, role) {
      channel = config.signalingChannel || null;
      if (!channel) {
        throw new Error('A signaling channel is required.');
      }

      await channel.subscribe();
      channel.on('broadcast', { event: 'webrtc' }, (payload) => {
        if (payload.payload?.callId === callId) {
          handleSignal(payload.payload.signal).catch((error) => {
            if (config.onError) {
              config.onError(error);
            }
          });
        }
      });
      return channel;
    }

    async function sendSignal(callId, signal) {
      if (!channel) {
        throw new Error('Signaling channel not connected.');
      }
      await channel.send({
        type: 'broadcast',
        event: 'webrtc',
        payload: { callId, signal },
      });
    }

    async function cleanup() {
      localStream?.getTracks().forEach((track) => track.stop());
      localStream = null;
      if (peerConnection) {
        peerConnection.close();
        peerConnection = null;
      }
      if (channel) {
        channel.unsubscribe();
        channel = null;
      }
    }

    return {
      ensureMedia,
      createOffer,
      createAnswer,
      handleSignal,
      joinChannel,
      sendSignal,
      cleanup,
      getLocalStream: () => localStream,
      getRemoteStream: () => remoteStream,
    };
  }

  global.createWebRTCSession = createWebRTCSession;
})(typeof window !== 'undefined' ? window : this);
