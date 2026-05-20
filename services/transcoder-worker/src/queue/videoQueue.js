const queue = []
let processingId = null

function enqueue(videoId) {
  if (processingId === videoId) return false
  if (queue.includes(videoId)) return false
  queue.push(videoId)
  return true
}

function dequeue() {
  return queue.shift() ?? null
}

function setProcessing(videoId) {
  processingId = videoId
}

function clearProcessing() {
  processingId = null
}

function getProcessingId() {
  return processingId
}

function size() {
  return queue.length
}

function peek() {
  return queue[0] ?? null
}

module.exports = { enqueue, dequeue, peek, setProcessing, clearProcessing, getProcessingId, size }
