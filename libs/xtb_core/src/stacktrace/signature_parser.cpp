#include <xtb_core/array.h>
#include <xtb_core/string.h>

namespace xtb::sigparse
{
enum class TokenKind
{
    Identifier,
    NamespaceSeparator,
    Pointer,
    LVReference,
    RVReference,
    LeftParen,
    RightParen,
    Comma,
    Const,
    Volatile,
    DotDotDot,
};

enum class IdentType
{
    None,
    Namespace,
    Function,
    Type,
};

struct Token
{
    TokenKind kind;
    String source_string;
    IdentType ident_type;
};

bool is_integer_character(u8 ch)
{
    return (ch >= '0' && ch <= '9');
}

bool is_identifier_character(u8 ch)
{
    return false
        || (ch >= 'a' && ch <= 'z')
        || (ch >= 'A' && ch <= 'Z')
        || (ch == '_')
        || is_integer_character(ch);
}

struct Lexer
{
    Allocator* m_allocator;
    String m_input;
    String m_rest;

    explicit Lexer(Allocator* allocator, String input)
        : m_allocator(allocator), m_input(input), m_rest(input) {}

    static Lexer from_string(Allocator* allocator, String input)
    {
        return Lexer(allocator, input);
    }

    bool next_token(Token* token)
    {
        m_rest = m_rest.trim_left();
        if (m_rest.is_empty()) return false;

        bool parsed = false
            || parse_simple_token(token, "*", TokenKind::Pointer)
            || parse_simple_token(token, "&", TokenKind::LVReference)
            || parse_simple_token(token, "(", TokenKind::LeftParen)
            || parse_simple_token(token, ")", TokenKind::RightParen)
            || parse_simple_token(token, ",", TokenKind::Comma)
            || parse_simple_token(token, "&&", TokenKind::RVReference)
            || parse_simple_token(token, "::", TokenKind::NamespaceSeparator)
            || parse_simple_token(token, "...", TokenKind::DotDotDot)
            || parse_simple_token(token, "const", TokenKind::Const)
            || parse_simple_token(token, "volatile", TokenKind::Volatile)
            || parse_identifier(token);

        return parsed;
    }

    bool parse_identifier(Token* token)
    {
        if (is_integer_character(m_rest[0])) return false;

        isize end_idx = 0;
        while (is_identifier_character(m_rest[end_idx]))
        {
            ++end_idx;
        }

        if (end_idx > 0)
        {
            String identifier = m_rest.head(end_idx);

            *token = {
                .kind = TokenKind::Identifier,
                .source_string = identifier,
                .ident_type = IdentType::None,
            };

            m_rest = m_rest.trunc_left(identifier.len());
            return true;
        }

        return false;
    }

    bool parse_simple_token(Token* token, String token_string, TokenKind token_kind)
    {
        if (m_rest.starts_with(token_string))
        {
            *token = {
                .kind = token_kind,
                .source_string = m_rest.substr(0, token_string.len()),
            };

            m_rest = m_rest.trunc_left(token_string.len());
            return true;
        }

        return false;
    }
};

void resolve_ident_type(SliceMut<Token> tokens)
{
    bool inside_parameter_list = false;

    for (isize i = 0; i < tokens.size(); ++i)
    {
        auto* token = &tokens[i];

        switch (token->kind)
        {
            case TokenKind::Identifier:
            {
                if (tokens.size() == 1)
                {
                    token->ident_type = IdentType::Function;
                }
                if (i != tokens.size() - 1)
                {
                    const auto* next_token = &tokens[i + 1];

                    if (next_token->kind == TokenKind::NamespaceSeparator)
                    {
                        token->ident_type = IdentType::Namespace;
                    }
                    else if (inside_parameter_list)
                    {
                        token->ident_type = IdentType::Type;
                    }
                    else
                    {
                        token->ident_type = IdentType::Function;
                    }
                }
            } break;

            case TokenKind::LeftParen:
            {
                inside_parameter_list = true;
            } break;

            default: {}
        }
    }
}

Array<Token> tokenize(Allocator* allocator, String input)
{
    auto lexer = Lexer::from_string(allocator, input);
    auto tokens = Array<Token>::init(allocator);

    Token token = {};
    while (lexer.next_token(&token))
    {
        tokens.append(token);
    }

    resolve_ident_type(tokens);

    return tokens;
}
}
