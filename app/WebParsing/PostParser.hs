module WebParsing.PostParser
    (getPost) where

import Network.HTTP
import qualified Data.Text as T
import Control.Monad.Trans (liftIO)
import Text.HTML.TagSoup
import Text.HTML.TagSoup.Match
import Config (databasePath)
import Database.Tables
import Database.Persist.Sqlite (insert_, runMigration, runSqlite, SqlPersistM)
import Database.Persist (insertUnique)
import qualified Text.Parsec as P
import WebParsing.ParsecCombinators (getCourseFromTag, generalCategoryParser, parseCategory,
    postInfoParser)

fasCalendarURL :: String
fasCalendarURL = "http://calendar.artsci.utoronto.ca/"

failedString :: String
failedString = "Failed."

getPost :: T.Text -> IO ()
getPost str = do
    let path = fasCalendarURL ++ (T.unpack str)
    rsp <- simpleHTTP (getRequest path)
    body <- getResponseBody rsp
    let tags = filter isNotComment $ parseTags body
        postsSoup = secondH2 tags
        posts = partitions isPostName postsSoup
    runSqlite databasePath $ do
        runMigration migrateAll
        mapM_ addPostToDatabase posts
    print $ "parsing " ++ (T.unpack str)
    where
        isNotComment (TagComment _) = False
        isNotComment _ = True
        secondH2 tags =
            let sect = sections (isTagOpenName "h2") tags
            in
                if (length sect) < 2
                then
                    []
                else
                    takeWhile isNotCoursesSection tags
        isNotCoursesSection tag = not (tagOpenAttrLit "a" ("name", "courses") tag)
        isPostName tag = tagOpenAttrNameLit "a" "name" (\nameValue -> (length nameValue) == 9) tag

addPostToDatabase :: [Tag String] -> SqlPersistM ()
addPostToDatabase tags = do
    let postCode_ = T.pack (fromAttrib "name" ((take 1 $ filter (isTagOpenName "a") tags) !! 0))
        liPartitions = partitions isLiTag tags
        programPrereqs = map getCourseFromTag $ map (T.pack . fromAttrib "href") $ filter isCourseTag tags
        firstCourse = if (null programPrereqs) then Nothing else (Just (head programPrereqs))
    categoryParser tags firstCourse postCode_ liPartitions
    where
        isCourseTag tag = tagOpenAttrNameLit "a" "href" (\hrefValue -> (length hrefValue) >= 0) tag
        isLiTag tag = isTagOpenName "li" tag

addPostCategoriesToDatabase :: T.Text -> [T.Text] -> SqlPersistM ()
addPostCategoriesToDatabase postCode_ categories = do
    mapM_ (addCategoryToDatabase postCode_) (filter isCategory categories)
    where
        isCategory text =
            let infixes = map (containsText text)
                         ["First", "Second", "Third", "suitable", "Core", "Electives"]
            in
                ((T.length text) >= 7) && ((length $ filter (\bool -> bool) infixes) <= 0)
        containsText text subtext = T.isInfixOf subtext text

addCategoryToDatabase :: T.Text -> T.Text -> SqlPersistM ()
addCategoryToDatabase postCode_ category =
    insert_ $ PostCategory category postCode_


-- Helpers

categoryParser :: [Tag String] -> Maybe T.Text -> T.Text -> [[Tag String]] -> SqlPersistM ()
categoryParser tags firstCourse postCode_ liPartitions = do
    case parsed of
        Right (post, categories) -> do
            postExist <- insertUnique post
            case postExist of
                Just _ -> addPostCategoriesToDatabase postCode_ categories
                Nothing -> return ()
        Left _ -> do
            liftIO $ print failedString
            return ()
    where
        parsed = case liPartitions of
            [] -> P.parse (generalCategoryParser firstCourse postCode_) failedString (T.pack $ innerText tags)
            partitionResults -> do
                let categories = map parseLi partitionResults
                post <- P.parse (postInfoParser firstCourse postCode_) failedString (T.pack $ innerText tags)
                return (post, categories)

parseLi :: [Tag String] -> T.Text
parseLi liPartition = do
    let parsed = P.parse parseCategory failedString (T.pack $ innerText liPartition)
    case parsed of
        Right category -> category
        Left _ -> ""
