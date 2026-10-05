const $ = selector => document.querySelector(selector);
let rateQueue = Promise.resolve();
let polling = false;
let initialized = false;
let rateEditing = false;
let rateDirty = false;
let rateRevision = 0;
let ratePending = 0;
let functionPending = 0;
let functionQueue = Promise.resolve();

async function callAPI(path, data) {
  const response = await fetch(path, data === undefined ? {} : {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data)
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || '전송 설정을 확인하세요.');
  return result;
}

function showStatus(data) {
  if (!rateEditing && !rateDirty && ratePending === 0 && Number.isInteger(data.target_rpm)) {
    $('#rate').value = data.target_rpm;
    showRate();
  }
  if (functionPending === 0 && ['projects', 'analyze'].includes(data.function)) {
    $('#function').value = data.function;
  }
  if (!initialized) {
    initialized = true;
    $('#rate').disabled = false;
    $('#function').disabled = false;
  }
  $('#running').textContent = data.running ? `전송 중 · 분당 ${data.target_rpm}건 설정` : '중지됨';
  $('#sent-minute').textContent = data.sent_last_minute;
  $('#success-minute').textContent = data.success_last_minute;
  $('#success').textContent = data.success;
  $('#failed').textContent = data.failed;
  $('#latency').textContent = data.average_latency_ms;
  $('#pod').textContent = data.last_pod || '아직 응답 없음';
  $('#result').textContent = data.last_result || '아직 응답 없음';
  $('#error').textContent = data.last_error || '';
  $('#start').disabled = data.running || Number($('#rate').value) === 0;
  $('#stop').disabled = !data.running;
}

function showRate() {
  const rpm = Number($('#rate').value);
  $('#rate-label').textContent = rpm;
  $('#interval').textContent = rpm ? `${(60 / rpm).toFixed(2)}초마다 1회` : '요청 중지';
}

$('#rate').addEventListener('pointerdown', () => { rateEditing = true; });
document.addEventListener('pointerup', () => { rateEditing = false; });
$('#rate').addEventListener('keydown', () => { rateEditing = true; });
$('#rate').addEventListener('keyup', () => { rateEditing = false; });
$('#rate').addEventListener('blur', () => { rateEditing = false; });
$('#rate').addEventListener('input', () => {
  rateDirty = true;
  rateRevision += 1;
  showRate();
});
$('#function').addEventListener('change', () => {
  const selected = $('#function').value;
  functionPending += 1;
  functionQueue = functionQueue.catch(() => {}).then(async () => {
    const data = await callAPI('/api/function', {function: selected});
    functionPending -= 1;
    showStatus(data);
    $('#control-message').textContent = '선택한 API로 다음 요청을 보냅니다.';
  }).catch(error => {
    functionPending -= 1;
    $('#error').textContent = error.message;
  });
});
$('#rate').addEventListener('change', () => {
  const rpm = Number($('#rate').value);
  const revision = rateRevision;
  ratePending += 1;
  rateQueue = rateQueue.catch(() => {}).then(async () => {
    const data = await callAPI('/api/rate', {rpm});
    ratePending -= 1;
    if (revision === rateRevision) rateDirty = false;
    showStatus(data);
    $('#control-message').textContent = `분당 ${rpm}건으로 설정했습니다.`;
  }).catch(error => {
    ratePending -= 1;
    if (revision === rateRevision) rateDirty = false;
    $('#error').textContent = error.message;
  });
});

$('#start').addEventListener('click', async () => {
  $('#start').disabled = true;
  try {
    await rateQueue;
    await functionQueue;
    await callAPI('/api/rate', {rpm: Number($('#rate').value)});
    await callAPI('/api/function', {function: $('#function').value});
    showStatus(await callAPI('/api/start', {}));
    $('#control-message').textContent = 'week6으로 요청을 보냅니다. 대시보드에서 요청 수와 Pod 수를 확인하세요.';
  } catch(error) { $('#error').textContent = error.message; $('#start').disabled = false; }
});

$('#stop').addEventListener('click', async () => {
  try {
    showStatus(await callAPI('/api/stop', {}));
    $('#control-message').textContent = '요청을 중지했습니다. 이미 전송 중인 요청은 완료될 수 있습니다.';
  } catch(error) { $('#error').textContent = error.message; }
});

async function poll() {
  if (polling) return;
  polling = true;
  try { showStatus(await callAPI('/api/status')); }
  catch(error) { $('#error').textContent = '발생기 연결 실패: Docker Compose 실행 상태를 확인하세요.'; }
  finally { polling = false; }
}
$('#rate').disabled = true;
$('#function').disabled = true;
$('#start').disabled = true;
$('#stop').disabled = true;
$('#rate-label').textContent = '확인 중';
$('#interval').textContent = '서버 설정 확인 중';
poll();
setInterval(poll, 1000);
