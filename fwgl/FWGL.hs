{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies,
             GeneralizedNewtypeDeriving, ExistentialQuantification #-}

{-|
    The main module. You should also import a backend:

        * FWGL.Backend.JavaScript: GHCJS/WebGL backend (contained in fwgl-javascript)
        * FWGL.Backend.GLFW.GL20: GLFW/OpenGL 2.0 backend (contained in fwgl-glfw)


    And a graphics system:

        * "FWGL.Graphics.D2": 2D graphics
        * "FWGL.Graphics.D3": 3D graphics
        * "FWGL.Graphics.Generic"


    "FWGL.Shader" contains the EDSL to make custom shaders.

    Import "FWGL.Internal.GL" if you want to use the raw GL commands.
-}
module FWGL (
        -- module FWGL.Audio,
        module FWGL.Input,
        module FRP.Yampa,
        BackendM(..),
        backend,
        mapIO,
        -- * FRP interface
        Output,
        run,
        run',
        runTo,
        draw,
        -- * File loading
        loadOBJ,
        loadOBJAsync,
        loadTextFileAsync,
        -- * Effect monad
        Effect,
        eff,
        drawEff,
        drawMEff,
        fastStep,
        -- ** Lifting functions
        liftIO,
        liftDraw,
        -- ** Window/Canvas
        setSize,
        setTitle,
        -- * Draw monad (for advanced use)
        Draw,
        drawM,
        -- ** Drawing
        drawLayer,
        drawGroup,
        drawObject,
        setProgram,
        renderLayer,
        resizeViewport,
        gl,
        -- ** Texture functions
        textureUniform,
        textureSize,
        -- ** Resources
        removeGeometry,
        removeTexture,
        removeProgram,
        -- * IO interface
        runIO,
        runToIO
) where

import Data.IORef
import qualified Data.HashMap.Strict as H
import Control.Applicative
import Control.Concurrent
import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.Trans.Reader
import Data.Vect.Float
-- import FWGL.Audio
import FWGL.Backend hiding (Texture, Program)
import FWGL.Input
import FWGL.Internal.GL (evalGL)
import FWGL.Geometry (Geometry3D)
import FWGL.Geometry.OBJ
import FWGL.Graphics.Draw
import FWGL.Graphics.Types
import FWGL.Shader.Program (Program)
import FRP.Yampa

-- | The general output.
data Output = forall a. Output Bool (Either (Effect ())
                                            (Draw a, a -> Effect ()))

newtype Effect a = Effect (ReaderT (Canvas, BackendState) Draw a)
        deriving (Functor, Applicative, Monad, MonadIO)

-- | Draw some layers. Short for:
-- 
-- > drawM . mapM_ drawLayer
draw :: BackendIO => [Layer] -> Output
draw = drawM . mapM_ drawLayer

-- | Run a 'Draw' action.
drawM :: Draw () -> Output
drawM d = Output False $ Right (d, \_ -> return ())

-- | Perform an effect.
eff :: Effect () -> Output
eff = Output False . Left

-- | Draw some layers and perform an effect.
drawEff :: BackendIO => [Layer] -> Effect () -> Output
drawEff layers eff = drawMEff (mapM_ drawLayer layers) $ const eff

-- | Run a 'Draw' action and perform an effect.
drawMEff :: Draw a -> (a -> Effect ()) -> Output
drawMEff = curry $ Output False . Right

-- | Use this instead of 'eff' when you want the next sample to be performed
-- immediately (e.g. when you need to produce some computationally expensive
-- effectful input at the request of the signal function).
fastStep :: Effect () -> Output
fastStep = Output True . Left

-- | Perform a 'Draw' effect. Note that ('eff' . liftDraw) is different from
-- 'drawM': you have to use drawM to actually draw something on the screen. 
-- liftDraw should be used to modify the state of the context, to get some
-- information from it, to render a 'Layer' on a 'Texture', ecc.
liftDraw :: Draw a -> Effect a
liftDraw c = Effect . ReaderT $ const c

-- | Set canvas/window size.
setSize :: BackendIO
        => Int -- ^ Width
        -> Int -- ^ Height
        -> Effect ()
setSize w h = Effect $ ask >>= \(canvas, bs) ->
                liftIO $ setCanvasSize w h canvas bs

-- | Set window title.
setTitle :: BackendIO => String -> Effect ()
setTitle title = Effect $ ask >>= \(canvas, bs) ->
                liftIO $ setCanvasTitle title canvas bs

newtype BackendM a = BackendM (ReaderT BackendState IO a)
        deriving (Functor, Applicative, Monad, MonadIO)

-- | Initialize the backend, run the action and terminate it.
backend :: BackendIO => BackendM () -> IO ()
backend (BackendM a) = do bs <- initBackend
                          runReaderT a bs
                          terminateBackend bs

-- | Useful for functions like 'forkIO' and 'forkOS'.
mapIO :: (IO a -> IO b) -> BackendM a -> BackendM b
mapIO f (BackendM a) = BackendM ask >>= liftIO . f . runReaderT a

-- | Run a FWGL program on a new canvas/window.
run :: BackendIO
    => SF (Input ()) Output  -- ^ Main signal
    -> BackendM ()
run = run' $ return ()

-- | Run a FWGL program, using custom inputs.
run' :: BackendIO
     => IO inp                -- ^ An IO effect generating the custom inputs.
     -> SF (Input inp) Output
     -> BackendM ()
run' = runTo "canvas"

-- | Run a FWGL program, using custom inputs and a specified canvas.
runTo :: BackendIO
      => String -- ^ Destination canvas (eg. "#myCanvasId"). This has
                -- meaning only in the JavaScript backend.
      -> IO inp -- ^ An IO effect generating the custom inputs.
      -> SF (Input inp) Output
      -> BackendM ()
runTo dest customInput sigf =
        do initCustom <- liftIO customInput
           outputRef <- liftIO . newIORef . eff $ return ()
           reactHandleRef <- liftIO . newIORef $ error "react before reactInit."
           
           runToIO dest
                (\w h -> writeIORef reactHandleRef =<<
                                reactInit (return $ initInput w h initCustom)
                                          (\_ _ -> (>> return False) .
                                                   writeIORef outputRef)
                                          sigf)
                $ \tmdiff inp ->
                   do custom <- customInput
                      reactStateRef <- readIORef reactHandleRef
                      react reactStateRef
                            (tmdiff, Just inp { inputCustom = custom })
                      readIORef outputRef
        
        where initInput w h = Input $ H.singleton Resize [
                        emptyEventData {
                                dataFramebufferSize = Just (w, h)
                        }]

              emptyEventData = EventData {
                                dataFramebufferSize = Nothing,
                                dataPointer = Nothing,
                                dataButton = Nothing,
                                dataKey = Nothing,
                                dataTime = 0 }

-- | Run a non-reactive FWGL program.
runIO :: BackendIO
      => (Double -> Input () -> IO Output) -- ^ Loop function
      -> BackendM ()
runIO = runToIO "canvas" $ \_ _ -> return ()

-- | Run a non-reactive FWGL program in a specified canvas.
runToIO :: BackendIO
        => String -- ^ Destination canvas (eg. "#myCanvasId"). This has
                  -- meaning only in the JavaScript backend.
        -> (Int -> Int -> IO ()) -- ^ Initialization function
        -> (Double -> Input () -> IO Output) -- ^ Loop function
        -> BackendM ()
runToIO dest init fun = BackendM $ ask >>= \bs -> liftIO $
        do (canvas, w, h) <- createCanvas dest bs
           init w h

           lastTimeRef <- getTime bs >>= newIORef
           newSizeRef <- newIORef Nothing
           drawStateVar <- drawCanvas (initState w h canvas) False canvas bs
                           >>= newMVar

           setCanvasResizeCallback (resizeCb newSizeRef) canvas bs

           setCanvasRefreshCallback (refreshCb lastTimeRef newSizeRef canvas
                                               bs drawStateVar)
                                    canvas bs

           refreshLoop 60 canvas bs

        where initState w h canvas = evalGL $ drawInit w h canvas

              resizeCb newSizeRef w h = writeIORef newSizeRef $ Just (w, h)

              refreshCb lastTimeRef newSizeRef canvas bs drawStateVar =
                      do tm <- readIORef lastTimeRef
                         tm' <- getTime bs
                         inp <- popInput () canvas bs
                         out <- fun ((tm' - tm) * 1000) inp
                         writeIORef lastTimeRef tm'
                         cycle lastTimeRef newSizeRef canvas
                               bs drawStateVar out

              cycle lastTimeRef newSizeRef canvas bs drawStateVar
                      (Output re edrawEff) =
                      do mNewSize <- readIORef newSizeRef
                         case edrawEff of
                              Right (drawAct, effFun) ->
                                      do r <- drawCanvas (drawTo $
                                              do case mNewSize of
                                                      Just (w, h) ->
                                                        do resizeViewport w h
                                                           liftIO $ writeIORef
                                                                newSizeRef
                                                                Nothing
                                                      Nothing -> return ()
                                                 drawBegin
                                                 r <- drawAct
                                                 drawEnd
                                                 return r) True canvas bs
                                         runEffect $ effFun r
                              Left eff -> runEffect eff
                         when re $ refreshCb lastTimeRef newSizeRef
                                             canvas bs drawStateVar
                      where drawTo drawAct ctx = modifyMVar drawStateVar $ \s ->
                                     flip evalGL ctx . fmap swap $
                                             runDraw drawAct s
                            runEffect (Effect e) =
                                drawCanvas (drawTo $ runReaderT e (canvas, bs))
                                           False canvas bs
                            swap (a, b) = (b, a)

-- | Load a model from an OBJ file asynchronously.
loadOBJAsync :: BackendIO 
             => FilePath -- ^ Path or URL.
             -> (Either String (Geometry Geometry3D) -> IO ()) -- ^ Callback.
             -> IO ()
loadOBJAsync fp k = loadTextFile fp $
                       \e -> case e of
                                  Left err -> k $ Left err
                                  Right str -> k . Right . geometryOBJ
                                                 . parseOBJ $ str

-- | Load a model from an OBJ file.
loadOBJ :: BackendIO => FilePath -> IO (Either String (Geometry Geometry3D))
loadOBJ fp = do var <- newEmptyMVar
                loadOBJAsync fp $ putMVar var
                takeMVar var

-- | Load a file asynchronously.
loadTextFileAsync :: BackendIO
                  => FilePath                           -- ^ Path or URL.
                  -> (Either String String -> IO ())    -- ^ Callback.
                  -> IO ()
loadTextFileAsync = loadTextFile
