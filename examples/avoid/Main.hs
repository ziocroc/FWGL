{-# LANGUAGE CPP #-}

module Main where

import Data.Fixed (mod')
import FWGL
import FWGL.Graphics.D3
import FRP.Yampa
import System.Random

#ifdef __GHCJS__
import FWGL.Backend.JavaScript
#else
import FWGL.Backend.GLFW.GL20
#endif

data Box = Box Vec3 Vec3

outline :: Color -> Texture
outline c = mkTexture 128 128 [ if x < 5 || y < 5 || x > 123 || y > 123
                                        then Color 0 50 50 255
                                        else c
                              | x <- [ 0 .. 127 ], y <- [ 0 .. 127 ] ]

walls :: RandomGen g => g -> SF (Input ()) [Box]
walls r = noiseR (- 1.8, 1.8) r >>> sscan (step (0 :: Int)) []
        where step len (b : bs) newX = advance b $ step (len + 1) bs newX
              step len [] newX = [ Box (Vec3 newX 1.8 (- 2)) (Vec3 0.2 0.1 0.1)
                                 | len < 40 && abs newX `mod'` 0.1 < 0.003 ]
              advance (Box (Vec3 x y z) hs) =
                      if - y < 1.4 then (Box (Vec3 x (y - 0.02) z) hs :)
                                   else id

car :: SF (Input ()) Box
car = pointer &&& size >>^ \((x, _), (width, _)) ->
        Box (Vec3 (fromIntegral (x * 3) / fromIntegral width - 1.5)
                  (- 0.8)
                  (- 2))
            (Vec3 0.1 0.1 0.1)

death :: SF (Box, [Box]) Bool
death = arrPrim $ \(c, ws) -> any (collision c) ws

collision :: Box -> Box -> Bool
collision (Box (Vec3 x y z) (Vec3 hx hy hz))
          (Box (Vec3 x' y' z') (Vec3 hx' hy' hz')) =
        not (abs (x - x') > (hx + hx') ||
             abs (y - y') > (hy + hy') ||
             abs (z - z') > (hz + hz'))

drawBox :: Texture -> Box -> Object3D
drawBox tex (Box p (Vec3 hx hy hz)) = trans p .
                                      scaleV (Vec3 hx hy hz) $
                                      cube tex

drawAll :: SF (Box, [Box]) [Object3D]
drawAll = arrPrim $ \(c, ws) -> drawBox outRed c : map (drawBox outWhite) ws
        where outRed = outline red
              outWhite = outline white

mainSig :: RandomGen g => g -> SF (Input ()) Output
mainSig r = car &&& walls r >>>
            drawAll &&& death >>^
            (\(objs, ded) -> if ded then redScreen else objs) >>^
            \objs -> draw [layerS $ viewPersp 0.3 1000 100 idmtx objs]
        where redScreen = [cube $ colorTex red]

main :: IO ()
main = newStdGen >>= backend . run . mainSig
