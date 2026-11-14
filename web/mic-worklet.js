// Sends mono frames (all input channels averaged) to the page. The output stays silent.
class MicrophoneCapture extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0];
    if (input && input.length) {
      const out = new Float32Array(input[0].length);
      for (const ch of input) for (let i = 0; i < out.length; i++) out[i] += ch[i] / input.length;
      this.port.postMessage(out);
    }
    return true;
  }
}
registerProcessor('microphone-capture', MicrophoneCapture);
