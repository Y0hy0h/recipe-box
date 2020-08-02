module SyncedStoreTest exposing (suite)

import Expect
import Fuzz
import Store.FilePath exposing (FilePath)
import Store.FolderPath exposing (FolderPath)
import Store.Store as Store exposing (Store)
import Store.SyncedStore as SyncedStore exposing (LocalStoreAccess, RemoteStoreAccess, SyncStateAccess, SyncedStore)
import Store.VersionStore as VersionStore exposing (VersionStore)
import Test exposing (..)
import TestUtils exposing (entriesFuzzer, filePathFuzzer, sortEntries)


suite : Test
suite =
    describe "synced store"
        [ fuzz2 filePathFuzzer Fuzz.int "inserts into both stores" <|
            \filePath item ->
                emptySyncedStore
                    |> SyncedStore.insert filePath item
                    |> expectEqualInAllStores filePath (Just item)
        , fuzz2 entriesFuzzer entriesFuzzer "sync results in same items in both stores" <|
            \localEntries remoteEntries ->
                let
                    localStore : LocalStore
                    localStore =
                        VersionStore.insertList VersionStore.empty localEntries

                    remoteStore : RemoteStore
                    remoteStore =
                        VersionStore.insertList VersionStore.empty remoteEntries
                in
                SyncedStore.with
                    { local = ( localStore, localStoreAccess )
                    , sync = ( Store.empty, syncStoreAccess )
                    , remote = ( remoteStore, remoteStoreAccess )
                    }
                    |> SyncedStore.sync []
                    |> (\syncedStore ->
                            let
                                locals =
                                    SyncedStore.local syncedStore
                                        |> VersionStore.listAll []
                                        |> List.map (\( path, ( item, _ ) ) -> ( path, item ))
                                        |> sortEntries

                                remotes =
                                    SyncedStore.remote syncedStore
                                        |> VersionStore.listAll []
                                        |> List.map (\( path, ( item, _ ) ) -> ( path, item ))
                                        |> sortEntries
                            in
                            locals
                                |> Expect.equalLists remotes
                       )
        ]


emptySyncedStore : SyncedStore LocalStore SyncStore RemoteStore Int
emptySyncedStore =
    SyncedStore.with
        { local = ( VersionStore.empty, localStoreAccess )
        , sync = ( Store.empty, syncStoreAccess )
        , remote = ( VersionStore.empty, remoteStoreAccess )
        }


type alias LocalStore =
    VersionStore Int


localStoreAccess : LocalStoreAccess LocalStore Int
localStoreAccess =
    { set = VersionStore.insert
    , insertWithRename = VersionStore.insertWithRename
    , read = VersionStore.read
    , delete = VersionStore.delete
    , listAll = VersionStore.listAll
    }


type alias SyncStore =
    Store SyncedStore.SyncState


syncStoreAccess : SyncStateAccess SyncStore
syncStoreAccess =
    { set = Store.insert
    , read = Store.read
    , delete = Store.delete
    , listAll = Store.listAll
    }


type alias RemoteStore =
    VersionStore Int


remoteStoreAccess : RemoteStoreAccess RemoteStore Int
remoteStoreAccess =
    { upload =
        \path item syncedVersion store ->
            let
                maybeExistingVersion =
                    VersionStore.read path store
                        |> Maybe.map Tuple.second
            in
            if maybeExistingVersion == syncedVersion then
                VersionStore.insert path item store
                    |> Tuple.mapFirst Just

            else
                ( Nothing, store )
    , download = \path store -> VersionStore.read path store
    , delete =
        \path version store ->
            let
                success =
                    (VersionStore.read path store
                        |> Maybe.map Tuple.second
                    )
                        == version

                newStore =
                    if success then
                        VersionStore.delete path store

                    else
                        store
            in
            ( success, newStore )
    , listAll =
        \folder store ->
            VersionStore.listAll folder store
    }



-- Expectation helpers


expectEqualInAllStores : FilePath -> Maybe Int -> SyncedStore LocalStore SyncStore RemoteStore Int -> Expect.Expectation
expectEqualInAllStores path expected syncedStore =
    let
        local =
            let
                actual =
                    VersionStore.read path (SyncedStore.local syncedStore)
                        |> Maybe.map (\( item, _ ) -> item)
            in
            if actual == expected then
                Nothing

            else
                Just ("Local store failed:\n\n" ++ reportInequality actual expected)

        remote =
            let
                actual =
                    SyncedStore.remote syncedStore
                        |> VersionStore.read path
                        |> Maybe.map (\( item, _ ) -> item)
            in
            if actual == expected then
                Nothing

            else
                Just ("Remote store failed:\n\n" ++ reportInequality actual expected)

        combined =
            String.join "\n\n\n" (List.filterMap identity [ local, remote ])
    in
    if String.isEmpty combined then
        Expect.pass

    else
        Expect.fail combined


reportInequality : item -> item -> String
reportInequality top bottom =
    String.join "\n"
        [ "    " ++ Debug.toString top
        , "    ╷"
        , "    │ Expect.equal"
        , "    ╵"
        , "    " ++ Debug.toString bottom
        ]
