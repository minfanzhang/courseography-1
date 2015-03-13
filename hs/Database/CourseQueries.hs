{-# LANGUAGE ScopedTypeVariables, OverloadedStrings #-}

module Database.CourseQueries (retrieveCourse, allCourses) where

import Database.Persist
import Database.Persist.Sqlite
import Database.Tables as Tables
import Control.Monad.IO.Class (liftIO)
import JsonResponse
import Database.JsonParser
import Happstack.Server
import qualified Data.Text as T
import qualified Data.Aeson as Aeson


retrieveCourse :: String -> ServerPart Response
retrieveCourse course =
    liftIO $ queryCourse (T.pack course)

-- | Queries the database for all information about `course`, constructs a JSON object
-- | representing the course and returns the appropriate JSON response.
queryCourse :: T.Text -> IO Response
queryCourse lowerStr =
    runSqlite dbStr $ do
        let courseStr = T.toUpper lowerStr
        sqlCourse :: [Entity Courses] <- selectList [CoursesCode ==. courseStr] []
        sqlLecturesFall    :: [Entity Lectures]   <- selectList [LecturesCode  ==. courseStr,
                                                                 LecturesSession ==. "F"] []
        sqlLecturesSpring  :: [Entity Lectures]   <- selectList [LecturesCode  ==. courseStr,
                                                                 LecturesSession ==. "S"] []
        sqlLecturesYear    :: [Entity Lectures]   <- selectList [LecturesCode  ==. courseStr,
                                                                 LecturesSession ==. "Y"] []
        sqlTutorialsFall   :: [Entity Tutorials]  <- selectList [TutorialsCode ==. courseStr,
                                                                 TutorialsSession ==. "F"] []
        sqlTutorialsSpring :: [Entity Tutorials]  <- selectList [TutorialsCode ==. courseStr,
                                                                 TutorialsSession ==. "S"] []
        sqlTutorialsYear   :: [Entity Tutorials]  <- selectList [TutorialsCode ==. courseStr,
                                                                 TutorialsSession ==. "Y"] []
        let course        = entityVal $ head sqlCourse
            fallSession   = buildSession sqlLecturesFall sqlTutorialsFall
            springSession = buildSession sqlLecturesSpring sqlTutorialsSpring
            yearSession   = buildSession sqlLecturesYear sqlTutorialsYear
            courseJSON    = buildCourse fallSession springSession yearSession course
        return $ toResponse $ createJSONResponse $ encodeJSON $ Aeson.toJSON courseJSON

-- | Builds a Course structure from a tuple from the Courses table.
-- Some fields still need to be added in.
buildCourse :: Maybe Session -> Maybe Session -> Maybe Session -> Courses -> Course
buildCourse fallSession springSession yearSession course =
    Course (coursesBreadth course)
           (coursesDescription course)
           (coursesTitle course)
           Nothing
           fallSession
           springSession
           yearSession
           (coursesCode course)
           (coursesExclusions course)
           (coursesManualTutorialEnrolment course)
           (coursesDistribution course)
           Nothing

-- | Builds a Lecture structure from a tuple from the Lectures table.
buildLecture :: Lectures -> Lecture
buildLecture entity =
    Lecture (lecturesExtra entity)
            (lecturesSection entity)
            (lecturesCapacity entity)
            (lecturesTimeStr entity)
            (map timeField (lecturesTimes entity))
            (lecturesInstructor entity)
            (Just (lecturesEnrolled entity))
            (Just (lecturesWaitlist entity))

-- | Builds a Tutorial structure from a tuple from the Tutorials table.
buildTutorial :: Tutorials -> Tutorial
buildTutorial entity =
    Tutorial (tutorialsSection entity)
             (map timeField (tutorialsTimes entity))
             (tutorialsTimeStr entity)

-- | Builds a Session structure from a list of tuples from the Lectures table, and a list of tuples from the Tutorials table.
buildSession :: [Entity Lectures] -> [Entity Tutorials] -> Maybe Tables.Session
buildSession lectures tutorials =
    Just $ Tables.Session (map (buildLecture . entityVal) lectures)
                          (map (buildTutorial . entityVal) tutorials)


-- | Build a list of all course codes in the database
allCourses :: IO Response
allCourses = do
  response <- runSqlite dbStr $ do
      courses :: [Entity Courses] <- selectList [] []
      let codes = map (coursesCode . entityVal) courses
      return $ T.unlines codes
  return $ toResponse response

