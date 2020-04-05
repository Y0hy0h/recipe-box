--module Recipe exposing (Ingredient, ParsingError, Quantity(..), Recipe, RecipePart(..), from, getListName, getQuantity, getText, ingredient, ingredientWithName, ingredients, map, parse)


module Recipe exposing (..)

import Dict exposing (Dict)
import Parser exposing ((|.), (|=), Parser)
import Set exposing (Set)


type Recipe
    = Recipe RecipeParts


type alias RecipeParts =
    List RecipePart


type RecipePart
    = PlainPart String
    | IngredientPart Ingredient


type Ingredient
    = Ingredient
        { text : String
        , quantity : Maybe Quantity
        , listName : Maybe String
        }


ingredient : String -> Maybe Quantity -> Ingredient
ingredient text quant =
    Ingredient
        { text = text
        , quantity = quant
        , listName = Nothing
        }


ingredientWithName : String -> Maybe Quantity -> String -> Ingredient
ingredientWithName text quant listName =
    Ingredient
        { text = text
        , quantity = quant
        , listName = Just listName
        }


getText : Ingredient -> String
getText (Ingredient ingred) =
    ingred.text


getQuantity : Ingredient -> Maybe Quantity
getQuantity (Ingredient ingred) =
    ingred.quantity


getListName : Ingredient -> String
getListName (Ingredient ingred) =
    Maybe.withDefault ingred.text ingred.listName


type Quantity
    = Amount Float
    | Measure Float String
    | Description String


from : RecipeParts -> Recipe
from parts =
    Recipe parts


parse : String -> Result ParsingError Recipe
parse input =
    Parser.run parseRecipe input
        |> Result.mapError deadEndsToString


type alias ParsingError =
    String


map : (RecipePart -> a) -> Recipe -> List a
map f (Recipe recipe) =
    List.map f recipe


ingredients : Recipe -> List Ingredient
ingredients (Recipe recipe) =
    List.filterMap
        (\part ->
            case part of
                IngredientPart ingred ->
                    Just ingred

                _ ->
                    Nothing
        )
        recipe



-- Parsing


parseRecipe : Parser Recipe
parseRecipe =
    Parser.loop [] parseRecursion


parseRecursion : RecipeParts -> Parser (Parser.Step RecipeParts Recipe)
parseRecursion state =
    Parser.oneOf
        [ Parser.succeed (\ingred -> Parser.Loop (ingred :: state))
            |= parseIngredient
        , Parser.succeed (\plain -> Parser.Loop (plain :: state))
            |= parsePlain
        , Parser.end |> Parser.map (\_ -> Parser.Done (Recipe <| List.reverse state))
        ]


parsePlain : Parser RecipePart
parsePlain =
    Parser.getChompedString (Parser.chompWhile (\c -> c /= '<'))
        |> Parser.andThen
            (\text ->
                if String.isEmpty text then
                    Parser.problem "Text cannot be empty"

                else
                    Parser.succeed (PlainPart text)
            )


parseIngredient : Parser RecipePart
parseIngredient =
    Parser.succeed
        (\text maybeMeta ->
            let
                ( maybeQuantity, maybeListName ) =
                    Maybe.withDefault ( Nothing, Nothing ) maybeMeta
            in
            IngredientPart
                (Ingredient
                    { text = String.trim text
                    , quantity = maybeQuantity
                    , listName = maybeListName
                    }
                )
        )
        |. Parser.symbol "<"
        |= parseInsideTextWithoutParens (Set.fromList [ '(', '>' ])
        |= parseOptional
            (Parser.succeed
                (\quant listName ->
                    ( quant, listName )
                )
                |. Parser.symbol "("
                |= parseOptional
                    (parseQuantity (Set.fromList [ ')', ':' ]))
                |= parseOptional
                    (Parser.succeed String.trim
                        |. Parser.symbol ":"
                        |= parseInsideTextWithParens (Set.fromList [ ')' ])
                    )
                |. Parser.symbol ")"
            )
        |. Parser.symbol ">"


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
                    |. Parser.symbol " "
                    |= parseInsideTextWithParens endChars
                )
        , parseDescription endChars
        ]


parseDescription : Set Char -> Parser Quantity
parseDescription endChars =
    Parser.succeed
        (\inside ->
            String.trim inside |> Description
        )
        |= parseInsideTextWithParens endChars


parseInsideTextWithoutParens : Set Char -> Parser String
parseInsideTextWithoutParens endChars =
    Parser.getChompedString (Parser.chompWhile (\c -> not (Set.member c endChars)))
        |> Parser.andThen
            (\text ->
                if String.isEmpty text then
                    Parser.problem "Inside text cannot be empty"

                else
                    Parser.succeed text
            )


parseInsideTextWithParens : Set Char -> Parser String
parseInsideTextWithParens endChars =
    Parser.getChompedString (chompParens endChars)
        |> Parser.andThen
            (\text ->
                if String.isEmpty text then
                    Parser.problem "Inside text cannot be empty"

                else
                    Parser.succeed text
            )


chompParens endChars =
    Parser.loop 0
        (\closeCount ->
            Parser.oneOf
                [ Parser.symbol "("
                    |> Parser.map
                        (\_ ->
                            Parser.Loop (closeCount + 1)
                        )
                , let
                    newCloseCount =
                        closeCount - 1
                  in
                  Parser.chompIf (\c -> c == ')' && newCloseCount >= 0)
                    |> Parser.map
                        (\_ ->
                            Parser.Loop newCloseCount
                        )
                , Parser.succeed (\first second -> second - first)
                    |= Parser.getOffset
                    |. Parser.chompWhile (\c -> (not <| Set.member c endChars) && c /= '(' && c /= ')')
                    |= Parser.getOffset
                    |> Parser.map
                        (\difference ->
                            if difference > 0 then
                                Parser.Loop closeCount

                            else
                                Parser.Done ()
                        )
                ]
        )


parseOptional : Parser a -> Parser (Maybe a)
parseOptional parser =
    Parser.oneOf
        [ parser |> Parser.map Just
        , Parser.succeed Nothing
        ]



-- Miscellaneous


{-|

    The official method is currently a placeholder.
    See https://github.com/elm/parser/issues/9

-}
deadEndsToString : List Parser.DeadEnd -> String
deadEndsToString deadEnds =
    String.concat (List.intersperse "; " (List.map deadEndToString deadEnds))


deadEndToString : Parser.DeadEnd -> String
deadEndToString deadend =
    problemToString deadend.problem ++ " at row " ++ String.fromInt deadend.row ++ ", col " ++ String.fromInt deadend.col


problemToString : Parser.Problem -> String
problemToString p =
    case p of
        Parser.Expecting s ->
            "expecting '" ++ s ++ "'"

        Parser.ExpectingInt ->
            "expecting int"

        Parser.ExpectingHex ->
            "expecting hex"

        Parser.ExpectingOctal ->
            "expecting octal"

        Parser.ExpectingBinary ->
            "expecting binary"

        Parser.ExpectingFloat ->
            "expecting float"

        Parser.ExpectingNumber ->
            "expecting number"

        Parser.ExpectingVariable ->
            "expecting variable"

        Parser.ExpectingSymbol s ->
            "expecting symbol '" ++ s ++ "'"

        Parser.ExpectingKeyword s ->
            "expecting keyword '" ++ s ++ "'"

        Parser.ExpectingEnd ->
            "expecting end"

        Parser.UnexpectedChar ->
            "unexpected char"

        Parser.Problem s ->
            "problem " ++ s

        Parser.BadRepeat ->
            "bad repeat"


{-| The built-in float parser has a bug with leading 'e's.
See <https://github.com/elm/parser/issues/28>
-}
parseFloat : Parser Float
parseFloat =
    Parser.backtrackable
        (Parser.oneOf
            [ Parser.symbol "e"
                |> Parser.andThen (\_ -> Parser.problem "A float cannot begin with e")
            , Parser.float
            ]
        )
