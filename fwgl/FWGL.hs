{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}

{-|
    The main module. You should also import a backend:

        * FWGL.Backend.JavaScript: GHCJS/WebGL backend (contained in fwgl-javascript)
        * FWGL.Backend.GLFW.GL20: GLFW/OpenGL 2.0 backend (contained in fwgl-glfw)


    And a graphics system:

        * "FWGL.Graphics.D2": 2D graphics
        * "FWGL.Graphics.D3": 3D graphics
        * "FWGL.Graphics.Custom": advanced custom graphics


    "FWGL.Shader" contains the EDSL to make custom shaders.
-}
module FWGL (
        module FWGL.Audio,
        module FWGL.Input,
        module FWGL.Utils,
        module FRP.Yampa,
        -- * Running
        run,
        run',
        -- * Effects
        Output,
        (.>),
        draw,
        io,
        freeGeometry,
        freeTexture,
        freeProgram,
        -- * OBJ loading
        loadOBJ,
        loadOBJAsync,
        -- TODO: resize, title ...
) where

import Control.Concurrent
import Control.Monad (void)
import Control.Monad.IO.Class
import FWGL.Audio
import FWGL.Backend hiding (Texture, Program)
import FWGL.Input
import FWGL.Internal.GL (evalGL)
import FWGL.Geometry (Geometry3)
import FWGL.Geometry.OBJ
import FWGL.Graphics.Draw
import FWGL.Graphics.Types
import FWGL.Shader.Program (Program)
import FWGL.Utils
import FRP.Yampa

-- | The general output.
newtype Output = Output { drawOutput :: Draw () }

-- | Compose two 'Output' effects.
(.>) :: Output -> Output -> Output
Output a .> Output b = Output $ a >> b

-- | Draw some layers.
draw :: BackendIO => [Layer] -> Output
draw layers = Output $ mapM_ drawLayer layers

-- | Perform an IO action.
io :: IO () -> Output
io = Output . liftIO

-- | Delete a 'Geometry' from the GPU.
freeGeometry :: BackendIO => Geometry i -> Output
freeGeometry = Output . void . removeGeometry

-- | Delete a 'Texture' from the GPU.
freeTexture :: BackendIO => Texture -> Output
freeTexture = Output . void . removeTexture

-- | Delete a 'Program' from the GPU.
freeProgram :: BackendIO => Program g i -> Output
freeProgram = Output . void . removeProgram

-- | Run a FWGL program.
run :: BackendIO
    => SF (Input ()) Output  -- ^ Main signal
    -> IO ()
run = run' $ return ()

-- | Run a FWGL program, using custom inputs.
run' :: BackendIO
     => IO inp                -- ^ An IO effect generating the custom inputs.
     -> SF (Input inp) Output
     -> IO ()
run' customInput sigf = setup initState loop customInput sigf
        where initState w h = evalGL $ drawInit w h
              loop (Output act) ctx drawState =
                      flip evalGL ctx . flip execDraw drawState $ do
                              drawBegin
                              act
                              drawEnd

-- | Load a model from an OBJ file asynchronously.
loadOBJAsync :: BackendIO 
             => FilePath
             -> (Either String (Geometry Geometry3) -> IO ())
             -> IO ()
loadOBJAsync fp k = loadTextFile fp $
                       \e -> case e of
                                  Left err -> k $ Left err
                                  Right str -> k . Right . geometryOBJ
                                                 . parseOBJ $ str

-- | Load a model from an OBJ file.
loadOBJ :: BackendIO => FilePath -> IO (Either String (Geometry Geometry3))
loadOBJ fp = do var <- newEmptyMVar
                loadOBJAsync fp $ putMVar var
                takeMVar var
