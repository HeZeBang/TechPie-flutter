/// Copy changes only when a new empty conversation starts. It never rotates on
/// a timer or replaces a user's draft while they are composing a message.
const genAiChatCopy = <({String hint, String title, String subtitle})>[
  (
    hint: '有什么想一起探索的？',
    title: '把想法，聊成答案。',
    subtitle: '一个问题，一点灵感，或一件想弄明白的事。',
  ),
  (
    hint: '从一个问题开始吧。',
    title: '今天，想弄懂什么？',
    subtitle: '从课上的疑问，到脑海里的新点子。',
  ),
  (
    hint: '把你的想法写在这里。',
    title: '给想法一个起点。',
    subtitle: '写下一句话，我们一起理清思路。',
  ),
  (
    hint: '有哪里需要一起理一理？',
    title: '慢慢想，一起解。',
    subtitle: '把复杂的问题，拆成清楚的小步骤。',
  ),
  (
    hint: '聊聊接下来想做的事。',
    title: '让灵感更进一步。',
    subtitle: '学习、写作、编程，都可以从这里开始。',
  ),
  (
    hint: '今天有什么新发现？',
    title: '留一点空间给好奇。',
    subtitle: '带着问题来，也带着新的思路离开。',
  ),
];
