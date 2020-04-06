--module Recipe exposing (Ingredient, ParsingError, Quantity(..), Recipe, RecipePart(..), RecipeParts, description, from, getListName, getQuantity, getText, ingredient, ingredientWithName, ingredients, map, parse, title)


module Recipe exposing (..)

import Parser exposing ((|.), (|=), Parser)
import Set exposing (Set)


type Recipe
    = Recipe { title : String, description : RecipeParts }


type alias RecipeParts =
    List (List RecipePart)


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


from : String -> RecipeParts -> Recipe
from t parts =
    Recipe
        { title = t
        , description = parts
        }


parse : String -> Result ParsingError Recipe
parse input =
    Parser.run parseRecipe input
        |> Result.mapError deadEndsToString


type alias ParsingError =
    String


map : (RecipePart -> a) -> Recipe -> List (List a)
map f (Recipe recipe) =
    List.map (\paragraph -> List.map f paragraph) recipe.description


title : Recipe -> String
title (Recipe recipe) =
    recipe.title


description : Recipe -> RecipeParts
description (Recipe recipe) =
    recipe.description


ingredients : RecipeParts -> List Ingredient
ingredients parts =
    List.concat parts
        |> List.filterMap
            (\part ->
                case part of
                    IngredientPart ingred ->
                        Just ingred

                    _ ->
                        Nothing
            )



-- Parsing


parseRecipe : Parser Recipe
parseRecipe =
    Parser.succeed
        (\t desc ->
            Recipe
                { title = t
                , description = desc
                }
        )
        |. Parser.symbol "# "
        |= Parser.getChompedString (Parser.chompUntil "\n")
        |. Parser.chompWhile (\c -> c == '\n')
        |= Parser.loop ( [], [] ) parseRecursion


parseRecursion : ( List RecipePart, RecipeParts ) -> Parser (Parser.Step ( List RecipePart, RecipeParts ) RecipeParts)
parseRecursion ( next, paragraphs ) =
    Parser.oneOf
        [ Parser.symbol "\n\n"
            |> Parser.map (\_ -> Parser.Loop ( [], List.reverse next :: paragraphs ))
        , Parser.symbol "\n"
            |> Parser.map (\_ -> Parser.Loop ( PlainPart " " :: next, paragraphs ))
        , Parser.succeed (\ingred -> Parser.Loop ( ingred :: next, paragraphs ))
            |= parseIngredient
        , Parser.succeed (\plain -> Parser.Loop ( plain :: next, paragraphs ))
            |= parsePlain (Set.fromList [ '<', '\n' ])
        , Parser.end |> Parser.map (\_ -> Parser.Done (List.reverse next :: paragraphs |> List.reverse))
        ]


parsePlain : Set Char -> Parser RecipePart
parsePlain endChars =
    Parser.getChompedString (Parser.chompWhile (\c -> not (Set.member c endChars)))
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
        (\text maybeQuantity maybeListName ->
            IngredientPart
                (Ingredient
                    { text = String.trim text
                    , quantity = maybeQuantity
                    , listName = maybeListName
                    }
                )
        )
        |. Parser.symbol "<"
        |= parseUntil (Set.fromList [ ':', ';', '>' ])
        |= parseOptional
            (Parser.succeed identity
                |. Parser.symbol ":"
                |. parseWhitespace
                |= parseQuantity (Set.fromList [ ';', '>' ])
            )
        |= parseOptional
            (Parser.succeed String.trim
                |. Parser.symbol ";"
                |= parseUntil (Set.fromList [ '>' ])
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
                    Parser.problem "Inside text cannot be empty"

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
