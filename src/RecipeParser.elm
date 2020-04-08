module RecipeParser exposing (Failure, Problem(..), displayProblem, parse)

import Ingredient exposing (Quantity(..))
import Parser.Advanced as Parser exposing ((|.), (|=), Token(..))
import Recipe exposing (Part(..), Recipe)
import Set exposing (Set)


parse : String -> Result Failure Recipe
parse input =
    Parser.run parseRecipe input


type alias Failure =
    List (Parser.DeadEnd Context Problem)


type alias Context =
    ()


type alias Parser a =
    Parser.Parser Context Problem a


s : String -> Token Problem
s string =
    Token string (Expecting string)


parseRecipe : Parser Recipe
parseRecipe =
    Parser.succeed
        (\title method ->
            Recipe.from title method
        )
        |. Parser.symbol (s "# ")
        |= Parser.getChompedString (Parser.chompUntil (s "\n"))
        |. Parser.chompWhile (\c -> c == '\n')
        |= Parser.loop ( [], [] ) parseRecursion


parseRecursion : ( List Recipe.Part, Recipe.Parts ) -> Parser (Parser.Step ( List Recipe.Part, Recipe.Parts ) Recipe.Parts)
parseRecursion ( next, paragraphs ) =
    Parser.oneOf
        [ Parser.symbol (s "\n\n")
            |> Parser.map (\_ -> Parser.Loop ( [], List.reverse next :: paragraphs ))
        , Parser.symbol (s "\n")
            |> Parser.map (\_ -> Parser.Loop ( PlainPart " " :: next, paragraphs ))
        , Parser.succeed (\ingred -> Parser.Loop ( ingred :: next, paragraphs ))
            |= parseIngredient
        , Parser.succeed (\plain -> Parser.Loop ( plain :: next, paragraphs ))
            |= parsePlain (Set.fromList [ '<', '\n' ])
        , Parser.end ExpectingEnd |> Parser.map (\_ -> Parser.Done (List.reverse next :: paragraphs |> List.reverse))
        ]


parsePlain : Set Char -> Parser Recipe.Part
parsePlain endChars =
    Parser.getChompedString (Parser.chompWhile (\c -> not (Set.member c endChars)))
        |> Parser.andThen
            (\text ->
                if String.isEmpty text then
                    Parser.problem EmptyText

                else
                    Parser.succeed (PlainPart text)
            )


parseIngredient : Parser Recipe.Part
parseIngredient =
    Parser.succeed
        (\text maybeQuantity maybeListName ->
            IngredientPart
                (Ingredient.from
                    (String.trim text)
                    maybeQuantity
                    maybeListName
                )
        )
        |. Parser.symbol (s "<")
        |= parseUntil (Set.fromList [ ':', ';', '>' ])
        |= parseOptional
            (Parser.succeed identity
                |. Parser.symbol (s ":")
                |. parseWhitespace
                |= parseQuantity (Set.fromList [ ';', '>' ])
            )
        |= parseOptional
            (Parser.succeed String.trim
                |. Parser.symbol (s ";")
                |= parseUntil (Set.fromList [ '>' ])
            )
        |. Parser.symbol (s ">")


parseQuantity : Set Char -> Parser Quantity
parseQuantity endChars =
    Parser.oneOf
        [ Parser.succeed
            (\number maybeUnit ->
                case maybeUnit of
                    Just unit ->
                        Measure number unit

                    Nothing ->
                        Amount number
            )
            |= parseFloat
            |= parseOptional
                (Parser.succeed identity
                    |. Parser.symbol (s " ")
                    |= parseUntil endChars
                )
        , parseDescription endChars
        ]


parseDescription : Set Char -> Parser Quantity
parseDescription endChars =
    Parser.succeed
        (\inside ->
            String.trim inside |> Description
        )
        |= parseUntil endChars


parseUntil : Set Char -> Parser String
parseUntil endChars =
    Parser.getChompedString (Parser.chompWhile (\c -> not (Set.member c endChars)))
        |> Parser.andThen
            (\text ->
                if String.isEmpty text then
                    Parser.problem EmptyText

                else
                    Parser.succeed text
            )


parseOptional : Parser a -> Parser (Maybe a)
parseOptional parser =
    Parser.oneOf
        [ parser |> Parser.map Just
        , Parser.succeed Nothing
        ]


parseWhitespace : Parser ()
parseWhitespace =
    Parser.chompWhile (\c -> c == ' ' || c == '\t')


type Problem
    = Expecting String
    | ExpectingEnd
    | ExpectingFloat
    | InvalidNumber
    | EmptyText


displayProblem : Problem -> String
displayProblem problem =
    "Your text has problem."


{-| The built-in float parser has a bug with leading 'e's.
See <https://github.com/elm/parser/issues/28>
-}
parseFloat : Parser Float
parseFloat =
    Parser.backtrackable
        (Parser.oneOf
            [ Parser.symbol (s "e")
                |> Parser.andThen (\_ -> Parser.problem InvalidNumber)
            , Parser.float ExpectingFloat InvalidNumber
            ]
        )
