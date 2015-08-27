{-# LANGUAGE TypeFamilies, MultiParamTypeClasses, FunctionalDependencies #-}

-- FWGL.Shader.Variables? (+ loadUniform, loadAttribute, inputName, etc.)
module FWGL.Shader.CPU (UniformCPU(..), AttributeCPU(..)) where

import qualified Data.Int as CPU
import Data.Word (Word)
import Data.Typeable
import qualified FWGL.Shader.Language.Types as GPU
import FWGL.Internal.GL as CPU
import qualified Data.Vect.Float as CPU
import Prelude as CPU

-- | CPU types convertible to GPU types (as uniforms).
class Typeable g => UniformCPU c g | g -> c where
        setUniform :: UniformLocation -> g -> c -> GL ()

-- | CPU types convertible to GPU types (as attributes).
class Typeable g => AttributeCPU c g | g -> c where
        encodeAttribute :: g -> [c] -> GL Array
        setAttribute :: g -> GLUInt -> GL ()

instance GLES => UniformCPU CPU.Float GPU.Float where
        setUniform l _ v = uniform1f l v

{-
instance GLES => UniformCPU CPU.Int32 GPU.Int where
        setUniform l _ v = uniform1i l v

instance GLES => AttributeCPU CPU.Int32 GPU.Int where
        encodeAttribute _ a = liftIO $ encodeInts a
        setAttribute _ i = attr gl_INT i 1
-}

-- TODO: bool, samplercube, ivec*, bvec*

instance GLES => AttributeCPU CPU.Float GPU.Float where
        encodeAttribute _ a = liftIO $ encodeFloats a
        setAttribute _ i = attr gl_FLOAT i 1

instance GLES => UniformCPU CPU.ActiveTexture GPU.Sampler2D where
        setUniform l _ (CPU.ActiveTexture v) = uniform1i l $ fromIntegral v

instance GLES => UniformCPU CPU.Vec2 GPU.Vec2 where
        setUniform l _ (CPU.Vec2 x y) = uniform2f l x y

instance GLES => AttributeCPU CPU.Vec2 GPU.Vec2 where
        encodeAttribute _ a = liftIO $ encodeVec2s a
        setAttribute _ i = attr gl_FLOAT i 2

instance GLES => UniformCPU CPU.Vec3 GPU.Vec3 where
        setUniform l _ (CPU.Vec3 x y z) = uniform3f l x y z

instance GLES => AttributeCPU CPU.Vec3 GPU.Vec3 where
        encodeAttribute _ a = liftIO $ encodeVec3s a
        setAttribute _ i = attr gl_FLOAT i 3

instance GLES => UniformCPU CPU.Vec4 GPU.Vec4 where
        setUniform l _ (CPU.Vec4 x y z w) = uniform4f l x y z w

instance GLES => AttributeCPU CPU.Vec4 GPU.Vec4 where
        encodeAttribute _ a = liftIO $ encodeVec4s a
        setAttribute _ i = attr gl_FLOAT i 4

instance GLES => UniformCPU CPU.Mat2 GPU.Mat2 where
        setUniform l _ m = liftIO (encodeMat2 m) >>= uniformMatrix2fv l false

instance GLES => UniformCPU CPU.Mat3 GPU.Mat3 where
        setUniform l _ m = liftIO (encodeMat3 m) >>= uniformMatrix3fv l false

instance GLES => UniformCPU CPU.Mat4 GPU.Mat4 where
        setUniform l _ m = liftIO (encodeMat4 m) >>= uniformMatrix4fv l false

attr :: GLES => GLEnum -> GLUInt -> GLInt -> GL ()
attr t i s = vertexAttribPointer i s t false 0 nullGLPtr
