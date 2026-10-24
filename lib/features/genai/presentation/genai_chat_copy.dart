/// Copy changes only when a new empty conversation starts. It never rotates on
/// a timer or replaces a user's draft while they are composing a message.
const genAiChatCopy = <({String hint, String title})>[
  (
    hint: '有什么想一起探索的？',
    title: '把想法，聊成答案。',
  ),
  (
    hint: '从一个问题开始吧。',
    title: '今天，想弄懂什么？',
  ),
  (
    hint: '把你的想法写在这里。',
    title: '给想法一个起点。',
  ),
  (
    hint: '有哪里需要一起理一理？',
    title: '慢慢想，一起解。',
  ),
  (
    hint: '聊聊接下来想做的事。',
    title: '让灵感更进一步。',
  ),
  (
    hint: '今天有什么新发现？',
    title: '留一点空间给好奇。',
  ),
];
