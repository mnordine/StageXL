async function initialize() {
  const canvas = document.querySelector('#stage');
  const requestedBackend = new URLSearchParams(location.search).get('backend');
  const useWebGPU = requestedBackend !== 'webgl2' && navigator.gpu !== undefined;
  const THREE = await import(useWebGPU ? 'three/webgpu' : 'three');
  const renderer = useWebGPU ? new THREE.WebGPURenderer({
    canvas,
    alpha: true,
    antialias: false,
  }) : new THREE.WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    stencil: true,
  });
  if (useWebGPU) await renderer.init();
  renderer.autoClear = false;
  renderer.setClearAlpha(0);
  renderer.outputColorSpace = useWebGPU ? THREE.LinearSRGBColorSpace : THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
  camera.position.set(0, 0.15, 7.4);

  scene.add(new THREE.HemisphereLight(0x9bdcff, 0x18213a, 2.3));
  const keyLight = new THREE.DirectionalLight(0xffffff, 3.4);
  keyLight.position.set(3.5, 5.5, 4.5);
  keyLight.castShadow = true;
  keyLight.shadow.mapSize.set(1024, 1024);
  scene.add(keyLight);

  const rimLight = new THREE.PointLight(0x36ddff, 22, 12);
  rimLight.position.set(-3.5, 1.2, 2);
  scene.add(rimLight);

  const character = createCharacter(THREE);
  character.rotation.set(-0.04, 0.38, 0);
  character.position.y = -0.18;
  scene.add(character);

  const floor = new THREE.Mesh(
    new THREE.CircleGeometry(2.25, 64),
    new THREE.MeshStandardMaterial({
      color: 0x13223b,
      transparent: true,
      opacity: 0.72,
      roughness: 0.82,
      metalness: 0.15,
    }),
  );
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -2.03;
  floor.receiveShadow = true;
  scene.add(floor);

  let dragging = false;
  let lastX = 0;
  let lastY = 0;
  let targetRotationX = character.rotation.x;
  let targetRotationY = character.rotation.y;

  canvas.addEventListener('pointerdown', (event) => {
    dragging = true;
    lastX = event.clientX;
    lastY = event.clientY;
    canvas.setPointerCapture(event.pointerId);
    canvas.classList.add('is-grabbing');
  });

  canvas.addEventListener('pointermove', (event) => {
    if (!dragging) return;
    targetRotationY += (event.clientX - lastX) * 0.012;
    targetRotationX = THREE.MathUtils.clamp(
      targetRotationX + (event.clientY - lastY) * 0.008,
      -0.55,
      0.55,
    );
    lastX = event.clientX;
    lastY = event.clientY;
  });

  const stopDragging = (event) => {
    if (!dragging) return;
    dragging = false;
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    canvas.classList.remove('is-grabbing');
  };
  canvas.addEventListener('pointerup', stopDragging);
  canvas.addEventListener('pointercancel', stopDragging);

  const bridge = {
    context: renderer.getContext(),
    get rotationX() {
      return character.rotation.x;
    },
    get rotationY() {
      return character.rotation.y;
    },
    resize(width, height, pixelRatio) {
      renderer.setPixelRatio(pixelRatio);
      renderer.setSize(width, height, false);
      camera.aspect = width / Math.max(height, 1);
      camera.updateProjectionMatrix();
    },
    render(timeMilliseconds) {
      character.rotation.x = THREE.MathUtils.lerp(character.rotation.x, targetRotationX, 0.16);
      character.rotation.y = THREE.MathUtils.lerp(character.rotation.y, targetRotationY, 0.16);
      character.position.y = -0.18 + Math.sin(timeMilliseconds * 0.0017) * 0.035;

      if (!useWebGPU) renderer.resetState();
      renderer.clear(false, true, false);
      renderer.render(scene, camera);
    },
    backend: useWebGPU ? 'webgpu' : 'webgl2',
    webGLContext: useWebGPU ? null : renderer.getContext(),
    webGPUDevice: useWebGPU ? renderer.backend.device : null,
    webGPUCanvasContext: useWebGPU ? renderer.backend.getContext() : null,
    webGPUTextureFormat: useWebGPU ? navigator.gpu.getPreferredCanvasFormat() : null,
  };

  globalThis.stageXLThree = Object.freeze(bridge);
  globalThis.dispatchEvent(new Event('stagexl-three-ready'));
}

function createCharacter(THREE) {
  const root = new THREE.Group();
  const shell = new THREE.MeshStandardMaterial({
    color: 0x445cff,
    roughness: 0.26,
    metalness: 0.62,
  });
  const dark = new THREE.MeshStandardMaterial({
    color: 0x10182e,
    roughness: 0.38,
    metalness: 0.72,
  });
  const accent = new THREE.MeshStandardMaterial({
    color: 0x62eeff,
    emissive: 0x1599c0,
    emissiveIntensity: 2.1,
    roughness: 0.2,
    metalness: 0.35,
  });

  const addMesh = (geometry, material, position, scale = [1, 1, 1]) => {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(...position);
    mesh.scale.set(...scale);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    root.add(mesh);
    return mesh;
  };

  addMesh(new THREE.CapsuleGeometry(0.72, 0.78, 8, 20), shell, [0, -0.15, 0]);
  addMesh(new THREE.SphereGeometry(0.67, 32, 20), shell, [0, 1.18, 0]);
  addMesh(new THREE.BoxGeometry(0.96, 0.34, 0.28), dark, [0, 1.22, 0.56]);
  addMesh(new THREE.BoxGeometry(0.22, 0.08, 0.04), accent, [-0.23, 1.23, 0.72]);
  addMesh(new THREE.BoxGeometry(0.22, 0.08, 0.04), accent, [0.23, 1.23, 0.72]);
  addMesh(new THREE.CylinderGeometry(0.13, 0.13, 0.42, 16), dark, [0, 2.0, 0]);
  addMesh(new THREE.SphereGeometry(0.16, 16, 12), accent, [0, 2.25, 0]);

  for (const side of [-1, 1]) {
    addMesh(new THREE.SphereGeometry(0.25, 20, 14), dark, [side * 0.89, 0.42, 0]);
    const arm = addMesh(new THREE.CapsuleGeometry(0.2, 0.72, 6, 14), shell, [side * 1.03, -0.16, 0]);
    arm.rotation.z = side * -0.1;
    addMesh(new THREE.SphereGeometry(0.24, 20, 14), accent, [side * 1.08, -0.88, 0]);

    const leg = addMesh(new THREE.CapsuleGeometry(0.25, 0.72, 6, 14), dark, [side * 0.39, -1.35, 0]);
    leg.rotation.z = side * 0.035;
    addMesh(new THREE.BoxGeometry(0.58, 0.28, 0.88), shell, [side * 0.42, -1.91, 0.2]);
  }

  addMesh(new THREE.TorusGeometry(0.29, 0.075, 12, 28), accent, [0, -0.03, 0.73]);
  return root;
}

initialize().catch((error) => {
  console.error(error);
  globalThis.stageXLThreeError = error instanceof Error ? error.message : String(error);
  globalThis.dispatchEvent(new Event('stagexl-three-ready'));
});
