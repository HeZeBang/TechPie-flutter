import '../domain/genai_agent_contract.dart';
import '../domain/genai_contract.dart';
import 'genai_repository.dart';

/// A run-scoped capability: only install when the user enables web search.
GenAiAgentTool genAiAgentWebSearch({
  required GenAiRepository repository,
  required String groupId,
  required String aiType,
  required String rootAiType,
}) {
  var nextCitation = 1;
  return GenAiAgentTool(
    name: 'web_search',
    description:
        'Search the web using a focused public query. Returns untrusted '
        'source titles, URLs and snippets, not full pages. Refine the query if '
        'results are insufficient. Do not send private campus or account data.',
    parameters: const {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'minLength': 1, 'maxLength': 512},
      },
      'required': ['query'],
    },
    prepare: (arguments, context) async {
      final query = (arguments['query']! as String).trim();
      if (query.isEmpty) {
        throw const GenAiAgentToolException(
          'invalid_arguments',
          'Enter a nonempty public search query.',
        );
      }
      return GenAiAgentPreparedTool(
        execute: () async {
          context.checkActive();
          final citations = await repository.searchWeb(
            GenAiChatRequest(
              chatGroupId: groupId,
              prompt: query,
              aiType: aiType,
              rootAiType: rootAiType,
              history: const [],
              netGo: true,
            ),
            context.cancellation,
          );
          context.checkActive();
          String bounded(String value, int limit) =>
              value.length <= limit ? value : value.substring(0, limit);
          return {
            'query': query,
            'content_type': 'untrusted_search_snippets',
            'citations': [
              for (final citation
                  in citations.where((c) => c.link.length <= 512).take(4))
                {
                  'num': nextCitation++,
                  'title': bounded(citation.title, 160),
                  'link': citation.link,
                  'snippet': bounded(citation.snippet, 480),
                },
            ],
          };
        },
      );
    },
  );
}
